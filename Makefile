VERSION := $(shell cat VERSION)
APP := build/corgi-bar.app
BINARY := .build/release/corgi-bar

.PHONY: build app run install clean test showcase

# -emit-const-values leaves the compile-time values Siri's metadata
# processor reads (scripts/appintents.sh); the protocol list is the one
# Xcode uses for App Intents.
SWIFT_CONST := -Xswiftc -emit-const-values -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc $(CURDIR)/scripts/appintents-protocols.json

build:
	swift build -c release $(SWIFT_CONST)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/corgi-bar
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
	mkdir -p $(APP)/Contents/Resources
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	scripts/appintents.sh $(APP)
	codesign --force --deep --sign - $(APP)
	@echo "built $(APP) ($(VERSION))"

run: app
	open $(APP)

install: app
	rm -rf /Applications/corgi-bar.app
	cp -R $(APP) /Applications/corgi-bar.app
	@echo "installed /Applications/corgi-bar.app"

clean:
	rm -rf build .build

test:
	swift test

showcase:
	scripts/capture.sh
