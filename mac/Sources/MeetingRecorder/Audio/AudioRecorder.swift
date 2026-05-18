import AVFoundation
import Accelerate
import Foundation

/// Records microphone (and optionally system audio) to a 16-bit PCM WAV
/// file at the configured sample rate. Mirrors the Python implementation:
///
/// * mic stream from ``AVAudioEngine.inputNode``
/// * system stream from ``ScreenCaptureKit`` (see ``SystemAudioCapture``)
/// * both streams resampled to mono 16 kHz, mixed, clipped, and written
/// * RMS of each written block stored for the silence watchdog
final class AudioRecorder {
    struct Config {
        var sampleRate: Double = 16_000
        var captureSystemAudio: Bool = true
    }

    private let outputURL: URL
    private let config: Config
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var systemAudio: SystemAudioCapture?

    private let writeQueue = DispatchQueue(label: "ai.checkbox.MeetingRecorder.audio.write")
    private let stateLock = NSLock()

    private var framesWritten: AVAudioFramePosition = 0
    /// (mach time, rms) for blocks written in the last 5 minutes.
    private var rmsHistory: [(time: TimeInterval, rms: Double)] = []
    private let rmsHistorySeconds: TimeInterval = 300

    /// True while we're still mixing in system audio. Flipped to false if
    /// SCK fails to start or if no system block has arrived after a grace
    /// period — in either case we fall back to writing mic only so the WAV
    /// isn't empty.
    private var mixingSystemAudio: Bool = false
    private var firstMicAt: TimeInterval?
    /// Seconds after the first mic buffer before we give up waiting for
    /// system audio and start writing mic only.
    private let systemAudioGraceSeconds: TimeInterval = 1.5

    /// Latest mic block awaiting a matching system block (only used when
    /// system capture is on). nil → no buffered mic chunk.
    private var pendingMicBlock: [Float]?

    init(outputURL: URL, config: Config) {
        self.outputURL = outputURL
        self.config = config
    }

    // MARK: - Public

    func start() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: config.sampleRate,
            channels: 1,
            interleaved: true
        )!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: config.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        self.audioFile = file

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Tap delivers ~100 ms blocks at the input device's native rate; we
        // resample inside the callback so the rest of the pipeline runs at
        // 16 kHz mono.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleMicBuffer(buffer, sourceFormat: inputFormat, targetFormat: format)
        }
        try engine.start()

        if config.captureSystemAudio {
            let sys = SystemAudioCapture(sampleRate: config.sampleRate) { [weak self] samples in
                self?.handleSystemBlock(samples)
            }
            self.systemAudio = sys
            stateLock.lock(); mixingSystemAudio = true; stateLock.unlock()
            // Start asynchronously — if the user denies the permission prompt
            // we keep recording mic only rather than aborting.
            Task { [weak self] in
                do {
                    try await sys.start()
                } catch {
                    FileHandle.standardError.write(Data("[system-audio] start failed, mic only: \(error.localizedDescription)\n".utf8))
                    self?.disableSystemMixing()
                }
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        Task { await systemAudio?.stop() }
        writeQueue.sync {
            audioFile = nil
        }
    }

    var secondsRecorded: Double {
        Double(framesWritten) / config.sampleRate
    }

    /// Trailing seconds during which every recorded block had RMS below
    /// ``threshold``. Returns 0 if no audio has been written yet.
    func secondsSilent(threshold: Double) -> Double {
        stateLock.lock()
        let history = rmsHistory
        stateLock.unlock()
        guard let latest = history.last else { return 0 }
        var lastLoud: TimeInterval? = nil
        for entry in history.reversed() where entry.rms >= threshold {
            lastLoud = entry.time
            break
        }
        if let lastLoud { return latest.time - lastLoud }
        return latest.time - history.first!.time
    }

    // MARK: - Mic path

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer, sourceFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        guard let samples = resampleToMono16k(buffer: buffer, sourceFormat: sourceFormat) else { return }
        stateLock.lock()
        let mixing = mixingSystemAudio
        let now = ProcessInfo.processInfo.systemUptime
        if firstMicAt == nil { firstMicAt = now }
        let waited = now - (firstMicAt ?? now)
        stateLock.unlock()

        if mixing && waited < systemAudioGraceSeconds {
            stateLock.lock()
            pendingMicBlock = samples
            stateLock.unlock()
            return
        }
        // SCK never delivered a block within the grace window — give up and
        // write mic only so we don't end up with an empty WAV.
        if mixing { disableSystemMixing() }
        writeMixed(mic: samples, system: nil)
    }

    private func disableSystemMixing() {
        stateLock.lock()
        guard mixingSystemAudio else { stateLock.unlock(); return }
        mixingSystemAudio = false
        let leftover = pendingMicBlock
        pendingMicBlock = nil
        stateLock.unlock()
        if let leftover { writeMixed(mic: leftover, system: nil) }
    }

    // MARK: - System path

    private func handleSystemBlock(_ samples: [Float]) {
        stateLock.lock()
        // If we already fell back to mic-only, drop late SCK blocks so we
        // don't interleave them out of order.
        guard mixingSystemAudio else { stateLock.unlock(); return }
        let mic = pendingMicBlock
        pendingMicBlock = nil
        stateLock.unlock()
        writeMixed(mic: mic, system: samples)
    }

    // MARK: - Resample + write

    private func resampleToMono16k(buffer: AVAudioPCMBuffer, sourceFormat: AVAudioFormat) -> [Float]? {
        guard let mono = mixdownToMono(buffer) else { return nil }
        if sourceFormat.sampleRate == config.sampleRate { return mono }
        return linearResample(mono, from: sourceFormat.sampleRate, to: config.sampleRate)
    }

    private func mixdownToMono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        }
        var out = [Float](repeating: 0, count: frames)
        for c in 0..<channels {
            let ptr = channelData[c]
            vDSP_vadd(out, 1, ptr, 1, &out, 1, vDSP_Length(frames))
        }
        var scale = Float(1.0 / Double(channels))
        vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(frames))
        return out
    }

    /// Cheap linear-interpolation resampler. Good enough for speech; whisper
    /// is tolerant. Drop in a higher-quality resampler later if needed.
    private func linearResample(_ input: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        let ratio = sourceRate / targetRate
        let outCount = Int(Double(input.count) / ratio)
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let pos = Double(i) * ratio
            let i0 = Int(pos)
            let i1 = min(i0 + 1, input.count - 1)
            let frac = Float(pos - Double(i0))
            out[i] = input[i0] * (1 - frac) + input[i1] * frac
        }
        return out
    }

    private func writeMixed(mic: [Float]?, system: [Float]?) {
        let mixed: [Float]
        switch (mic, system) {
        case let (m?, s?):
            let n = min(m.count, s.count)
            var out = [Float](repeating: 0, count: n)
            vDSP_vadd(m, 1, s, 1, &out, 1, vDSP_Length(n))
            var scale: Float = 0.5
            vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(n))
            mixed = out
        case let (m?, nil):
            mixed = m
        case let (nil, s?):
            mixed = s
        default:
            return
        }
        if mixed.isEmpty { return }

        // Clip to [-1, 1] before int16 conversion.
        var clipped = mixed
        var low: Float = -1
        var high: Float = 1
        vDSP_vclip(clipped, 1, &low, &high, &clipped, 1, vDSP_Length(clipped.count))

        writeQueue.async { [weak self] in
            guard let self, let file = self.audioFile else { return }
            let format = file.processingFormat
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clipped.count)) else { return }
            pcm.frameLength = AVAudioFrameCount(clipped.count)
            if let ch = pcm.int16ChannelData {
                let dest = ch[0]
                var scale: Float = 32_767
                var scaled = [Float](repeating: 0, count: clipped.count)
                vDSP_vsmul(clipped, 1, &scale, &scaled, 1, vDSP_Length(clipped.count))
                for i in 0..<clipped.count {
                    dest[i] = Int16(max(-32_768, min(32_767, Int(scaled[i]))))
                }
            }
            do {
                try file.write(from: pcm)
                self.framesWritten += AVAudioFramePosition(clipped.count)
                let rms = self.computeRMS(clipped)
                self.recordRMS(rms)
            } catch {
                // Drop the block on write failure — the recording continues.
            }
        }
    }

    private func computeRMS(_ samples: [Float]) -> Double {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return Double(rms)
    }

    private func recordRMS(_ rms: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        rmsHistory.append((now, rms))
        let cutoff = now - rmsHistorySeconds
        while let first = rmsHistory.first, first.time < cutoff {
            rmsHistory.removeFirst()
        }
    }
}
