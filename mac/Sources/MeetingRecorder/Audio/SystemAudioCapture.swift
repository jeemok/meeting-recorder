import AVFoundation
import Foundation
import ScreenCaptureKit

/// Captures system audio on macOS 13+ via ``ScreenCaptureKit``. We start a
/// capture stream that *only* delivers audio — no video frames — by
/// configuring an opaque 2×2 frame and discarding video samples.
///
/// Mixed mono audio resampled to ``sampleRate`` is delivered to the
/// ``onSamples`` callback in ~100 ms blocks.
@available(macOS 13.0, *)
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let sampleRate: Double
    private let onSamples: ([Float]) -> Void
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "ai.checkbox.MeetingRecorder.scaudio")

    init(sampleRate: Double, onSamples: @escaping ([Float]) -> Void) {
        self.sampleRate = sampleRate
        self.onSamples = onSamples
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "no display"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = 1
        // We don't need video; use the smallest possible frame to minimise cost.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let samples = floatSamples(from: sampleBuffer) else { return }
        onSamples(samples)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Recoverable: mic-only recording continues. Logged via stderr.
        FileHandle.standardError.write(Data("[system-audio] stopped: \(error.localizedDescription)\n".utf8))
    }

    private func floatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let mData = audioBufferList.mBuffers.mData else { return nil }
        let byteSize = Int(audioBufferList.mBuffers.mDataByteSize)
        let count = byteSize / MemoryLayout<Float>.size
        let ptr = mData.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
}
