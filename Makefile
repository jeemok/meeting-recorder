.PHONY: help build build-release build-release-signed dmg reinstall run clean install-diarization diarize-check trust

APP        := mac/MeetingRecorder.app
PY_VENV    := .venv
PY_BIN     := $(PY_VENV)/bin

help:
	@echo "Targets:"
	@echo "  make build                 swift build (debug) → mac/MeetingRecorder.app"
	@echo "  make build-release         swift build (release)"
	@echo "  make build-release-signed  release + codesign (uses stable identity if 'make trust' was run)"
	@echo "  make dmg                   build-release-signed + package mac/MeetingRecorder-<version>.dmg"
	@echo "  make reinstall             quit app, rebuild, replace /Applications/MeetingRecorder.app, relaunch"
	@echo "  make trust                 create a stable self-signed identity so TCC remembers permissions"
	@echo "  make run                   build (debug) and launch the app"
	@echo "  make install-diarization   create .venv + install pyannote.audio"
	@echo "  make diarize-check         verify the diarization sidecar can import pyannote"
	@echo "  make clean                 remove build artifacts"

build:
	cd mac && ./build.sh debug

build-release:
	cd mac && ./build.sh release

build-release-signed:
	cd mac && ./build.sh release sign

dmg:
	mac/scripts/make_dmg.sh

reinstall:
	mac/scripts/reinstall.sh

trust:
	mac/scripts/setup_signing.sh

run: build
	open $(APP)

# Diarization sidecar venv. Only needed if you enable speaker diarization
# in Settings → Transcription. Everything else runs natively in Swift.
$(PY_VENV):
	python3 -m venv $(PY_VENV)
	$(PY_BIN)/pip install --upgrade pip

install-diarization: $(PY_VENV)
	$(PY_BIN)/pip install "pyannote.audio>=3.1.1" "torch>=2.1" "torchaudio>=2.1"

diarize-check: $(PY_VENV)
	$(PY_BIN)/python mac/Resources/diarize_sidecar.py --check

clean:
	rm -rf mac/.build mac/MeetingRecorder.app mac/MeetingRecorder-*.dmg $(PY_VENV) .pytest_cache .ruff_cache
