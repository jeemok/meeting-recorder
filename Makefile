.PHONY: help install install-dev install-diarization serve dev record devices suggest summarize list doctor test lint clean

VENV := .venv
BIN  := $(VENV)/bin
MR   := $(BIN)/meeting-recorder

help:
	@echo "Common targets:"
	@echo "  make install            create .venv and install package (editable)"
	@echo "  make install-dev        also install dev extras (pytest, ruff)"
	@echo "  make install-diarization also install pyannote/torch extras"
	@echo "  make serve              start the web UI"
	@echo "  make dev                start the web UI with --reload"
	@echo "  make record TITLE='...' start a recording"
	@echo "  make devices            list audio input devices"
	@echo "  make suggest ID=...     follow-up questions for an existing meeting"
	@echo "  make summarize ID=...   (re-)summarize an existing meeting"
	@echo "  make list               list saved meetings"
	@echo "  make doctor             run environment checks"
	@echo "  make test               run pytest"
	@echo "  make lint               run ruff"
	@echo "  make clean              remove .venv and caches"

$(VENV):
	python3 -m venv $(VENV)

install: $(VENV)
	$(BIN)/pip install -e .

install-dev: $(VENV)
	$(BIN)/pip install -e ".[dev]"

install-diarization: $(VENV)
	$(BIN)/pip install -e ".[diarization]"

serve:
	$(MR) serve

dev:
	$(MR) serve --reload

record:
	$(MR) record $(if $(TITLE),--title "$(TITLE)",)

devices:
	$(MR) devices

suggest:
	$(MR) suggest $(ID)

summarize:
	$(MR) summarize $(ID)

list:
	$(MR) list

doctor:
	$(MR) doctor

test:
	$(BIN)/pytest

lint:
	$(BIN)/ruff check src tests

clean:
	rm -rf $(VENV) .pytest_cache **/__pycache__
