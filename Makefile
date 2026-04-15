VERSION ?= 1.0.0-dev

.PHONY: all dylib dylib-test generate build test dmg bump clean

all: build

dylib:
	$(MAKE) -C macos/dylib

dylib-test:
	$(MAKE) -C macos/dylib test

generate:
	cd macos/installer && xcodegen generate

build:
	bash macos/scripts/build.sh

test: dylib-test
	cd macos/installer && xcodegen generate
	xcodebuild test \
		-project macos/installer/NimoInstaller.xcodeproj \
		-scheme Nimo \
		-destination "platform=macOS" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

dmg:
	bash macos/scripts/create-dmg.sh $(VERSION)

bump:
	@if [ -z "$(VERSION)" ] || [ "$(VERSION)" = "1.0.0-dev" ]; then \
		echo "error: pass VERSION=x.y.z (e.g. 'make bump VERSION=1.2.3')" >&2; exit 2; \
	fi
	bash macos/scripts/bump-version.sh $(VERSION)

clean:
	rm -rf build
	rm -rf macos/installer/NimoInstaller.xcodeproj
	$(MAKE) -C macos/dylib clean || true
