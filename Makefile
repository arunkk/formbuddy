PYTHON ?= python3.12
VENV ?= .venv
BIN = $(VENV)/bin

.PHONY: help venv install install-dev test run clean ios-generate ios-build ios-test

SIMULATOR ?= iPhone 18 Pro
XCODEBUILD = xcodebuild -workspace FormBuddy.xcworkspace -scheme FormBuddy -sdk iphonesimulator -destination 'platform=iOS Simulator,name=$(SIMULATOR)'

help:
	@echo "Targets:"
	@echo "  venv        Create the virtual environment"
	@echo "  install     Install the package (runtime deps only)"
	@echo "  install-dev Install the package with dev dependencies (pytest)"
	@echo "  test        Run the test suite"
	@echo "  run         Analyze a video: make run INPUT=path/to/video.mp4 [OUTPUT_DIR=out]"
	@echo "  ios-generate Regenerate FormBuddy.xcodeproj (runs pod install)"
	@echo "  ios-build   Build the iOS app (opens the workspace, not the project)"
	@echo "  ios-test    Run the iOS test suite in the simulator"
	@echo "  clean       Remove the venv and build artifacts"

venv:
	$(PYTHON) -m venv $(VENV)

install: venv
	$(BIN)/pip install -e .

install-dev: venv
	$(BIN)/pip install -e ".[dev]"

test: install-dev
	$(BIN)/python -m pytest tests/ -v

run: install
	$(BIN)/formbuddy --input $(INPUT) --output-dir $(or $(OUTPUT_DIR), ./out)

# The iOS app depends on MediaPipeTasksVision from CocoaPods, which only exists
# in FormBuddy.xcworkspace. Always build/test the workspace, never the project.
ios-generate:
	xcodegen generate

ios-build:
	$(XCODEBUILD) build

ios-test:
	$(XCODEBUILD) test

clean:
	rm -rf $(VENV) build dist src/*.egg-info .pytest_cache
	find . -type d -name __pycache__ -exec rm -rf {} +
