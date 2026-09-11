#!/bin/sh
# Writes Metadata.appintents into the app bundle: what Siri and Shortcuts
# read to learn the bar's intents. Xcode does this as a build phase; swift
# build does not, so `make app` runs the same tool by hand. Needs the build
# made with -emit-const-values (see the Makefile), which leaves the
# compile-time values the processor reads next to the objects.
set -e
APP=$1
[ -d "$APP" ] || { echo "usage: appintents.sh build/corgi-bar.app" >&2; exit 2; }
cd "$(dirname "$0")/.."
BUILD=$(swift build -c release --show-bin-path)
CONST="$BUILD/CorgiBar.build/CorgiBar.swiftconstvalues"
[ -f "$CONST" ] || { echo "no $CONST — build with -emit-const-values first" >&2; exit 1; }
TMP=$(mktemp -d)
ls "$PWD"/Sources/CorgiBar/*.swift > "$TMP/sources.txt"
echo "$CONST" > "$TMP/const.txt"
XCODE=$(xcodebuild -version | awk '/Build version/{print $3}')
ARCH=$(uname -m)
xcrun appintentsmetadataprocessor \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name CorgiBar \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$XCODE" \
  --platform-family macOS \
  --deployment-target 13.0 \
  --target-triple "$ARCH-apple-macos13.0" \
  --bundle-identifier com.andriiklymiuk.corgi-bar \
  --output "$APP/Contents/Resources" \
  --source-file-list "$TMP/sources.txt" \
  --swift-const-vals-list "$TMP/const.txt" \
  --binary-file "$APP/Contents/MacOS/corgi-bar" \
  --compile-time-extraction --deployment-aware-processing --validate-assistant-intents --quiet-warnings
rm -rf "$TMP"
test -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" || { echo "no intents metadata came out" >&2; exit 1; }
echo "intents: $(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(', '.join(sorted(a['identifier'] if isinstance(a,dict) else a for a in (d['actions'] if isinstance(d['actions'],list) else d['actions'].keys()))))" "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata")"
