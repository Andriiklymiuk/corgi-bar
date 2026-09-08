VERSION := $(shell cat VERSION)
APP := build/corgi-bar.app
BINARY := .build/release/corgi-bar

.PHONY: build app run install clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/corgi-bar
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(APP)/Contents/Info.plist
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
