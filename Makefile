PROJECT       := Feedini.xcodeproj
SCHEME        := Feedini
CONFIG        ?= Debug
DERIVED_DATA  := build/DerivedData
APP           := $(DERIVED_DATA)/Build/Products/$(CONFIG)/Feedini.app
SOURCES       := Shared Feedini FeediniMobile FeediniTests
ARCH          := $(shell uname -m)
INSTALL_DIR   ?= $(HOME)/Applications
RELEASE_APP   := $(DERIVED_DATA)/Build/Products/Release/Feedini.app
RESULT_BUNDLE := build/Test.xcresult

IOS_APP       := $(DERIVED_DATA)/Build/Products/$(CONFIG)-iphonesimulator/Feedini.app
SIMULATOR     ?= iPhone 17

XCODEBUILD    := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	-destination 'platform=macOS,arch=$(ARCH)' -derivedDataPath $(DERIVED_DATA) -quiet

.PHONY: build build-ios run-ios test coverage run install uninstall release publish format lint clean

build:
	$(XCODEBUILD) build

# The iOS app for the simulator, unsigned (it shares Shared/ with the Mac app).
build-ios:
	xcodebuild -project $(PROJECT) -scheme FeediniMobile -configuration $(CONFIG) \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) -quiet build

# Builds the iOS app and runs it in the simulator SIMULATOR (booted when needed) with the launch arguments ARGS, e.g.
# ARGS=-sampleLibrary (Debug only: made-up articles in a temporary library). See it with
# `xcrun simctl io booted screenshot <file>`.
run-ios: build-ios
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	xcrun simctl bootstatus "$(SIMULATOR)" -b >/dev/null
	xcrun simctl install "$(SIMULATOR)" "$(IOS_APP)"
	xcrun simctl launch --terminate-running-process "$(SIMULATOR)" cz.jsyrovy.feedini $(ARGS)

test:
	$(XCODEBUILD) test

# Coverage collection is enabled in the scheme (app target only); this keeps the result bundle and prints the report.
coverage:
	rm -rf "$(RESULT_BUNDLE)"
	$(XCODEBUILD) -resultBundlePath "$(RESULT_BUNDLE)" test
	xcrun xccov view --report --only-targets "$(RESULT_BUNDLE)"
	xcrun xccov view --report --files-for-target Feedini.app "$(RESULT_BUNDLE)"

run: build
	pkill -x Feedini || true
	open "$(APP)"

# Release build copied to INSTALL_DIR (default ~/Applications); stops any running Feedini, including a dev build.
install:
	$(MAKE) build CONFIG=Release
	pkill -x Feedini || true
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Feedini.app"
	ditto "$(RELEASE_APP)" "$(INSTALL_DIR)/Feedini.app"
	open "$(INSTALL_DIR)/Feedini.app"

uninstall:
	pkill -x Feedini || true
	rm -rf "$(INSTALL_DIR)/Feedini.app"

# Signed and notarized zip of a tagged commit in build/release (scripts/release.sh).
release:
	scripts/release.sh

# The release in build/release as a draft GitHub release of its pushed tag (scripts/publish.sh).
publish:
	scripts/publish.sh

format:
	xcrun swift-format format --in-place --recursive --parallel $(SOURCES)

lint:
	xcrun swift-format lint --strict --recursive --parallel $(SOURCES)

clean:
	rm -rf build
