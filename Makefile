.PHONY: help ios-generate ios-build ios-test ios-run

SIMULATOR ?= iPhone 18 Pro
XCODEBUILD = xcodebuild -workspace FormBuddy.xcworkspace -scheme FormBuddy -sdk iphonesimulator -destination 'platform=iOS Simulator,name=$(SIMULATOR)'
BUNDLE_ID ?= com.formbuddy.app

help:
	@echo "Targets:"
	@echo "  ios-generate Regenerate FormBuddy.xcodeproj (runs pod install)"
	@echo "  ios-build    Build the iOS app (uses the workspace, not the project)"
	@echo "  ios-test     Run the iOS test suite in the simulator"
	@echo "  ios-run      Build, install, and launch on the booted simulator"

# The iOS app depends on MediaPipeTasksVision from CocoaPods, which only exists
# in FormBuddy.xcworkspace. Always build/test the workspace, never the project.
ios-generate:
	xcodegen generate

ios-build:
	$(XCODEBUILD) build

ios-test:
	$(XCODEBUILD) test

ios-run: ios-build
	xcrun simctl boot "$(SIMULATOR)" || true
	xcrun simctl install booted "$$(xcodebuild -workspace FormBuddy.xcworkspace -scheme FormBuddy -sdk iphonesimulator -destination 'platform=iOS Simulator,name=$(SIMULATOR)' -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$$2} / FULL_PRODUCT_NAME /{n=$$2} END{print d "/" n}')"
	xcrun simctl launch booted $(BUNDLE_ID)
