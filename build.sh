#!/bin/sh
# Builds foo_coverflow_mac.component and the installable .fb2k-component.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$ROOT/vendor/sdk"
NAME="foo_coverflow_mac"
VERSION="0.2.2"
ARCH="arm64"
MIN_OS="14.0"
BUILD="$ROOT/build"
SDK_LIBS="$BUILD/sdk-dd/Build/Products/Release"
BUNDLE="$BUILD/$NAME.component"
PACKAGE="$BUILD/$NAME-$VERSION.fb2k-component"

# 0. foobar2000 SDK (downloaded once, not part of the repository)
SDK_VERSION="2026-10-01"
if [ ! -f "$SDK/foobar2000/SDK/foobar2000.h" ]; then
  echo "Downloading foobar2000 SDK $SDK_VERSION ..."
  mkdir -p "$SDK" "$BUILD"
  curl -fsSL -o "$BUILD/SDK-$SDK_VERSION.7z" "https://www.foobar2000.org/files/SDK-$SDK_VERSION.7z"
  bsdtar -xf "$BUILD/SDK-$SDK_VERSION.7z" -C "$SDK"
fi

# 1. foobar2000 SDK static libraries (built once)
if [ ! -f "$SDK_LIBS/libfoobar2000_SDK.a" ]; then
  xcodebuild -quiet \
    -workspace "$SDK/foobar2000/foo_sample/foo_sample.xcworkspace" \
    -scheme foo_sample -configuration Release \
    -derivedDataPath "$BUILD/sdk-dd" \
    ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET="$MIN_OS" build
fi

# 2. Compile
SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS="-arch $ARCH -mmacosx-version-min=$MIN_OS -isysroot $SYSROOT
  -std=gnu++20 -stdlib=libc++ -fobjc-arc -O2 -DNDEBUG=1
  -I$ROOT/src -I$SDK -I$SDK/foobar2000"

mkdir -p "$BUILD/obj" "$BUNDLE/Contents/MacOS"
OBJS=""
for f in "$ROOT"/src/*.cpp "$ROOT"/src/*.mm; do
  o="$BUILD/obj/$(basename "$f").o"
  case "$f" in *.mm) lang=objective-c++ ;; *) lang=c++ ;; esac
  clang++ $FLAGS -x $lang -c "$f" -o "$o"
  OBJS="$OBJS $o"
done

# 3. Link bundle
clang++ -arch $ARCH -mmacosx-version-min=$MIN_OS -isysroot "$SYSROOT" -bundle \
  -o "$BUNDLE/Contents/MacOS/$NAME" $OBJS \
  -L"$SDK_LIBS" \
  -lfoobar2000_component_client -lshared -lfoobar2000_SDK -lfoobar2000_SDK_helpers -lpfc \
  -framework Cocoa -framework QuartzCore -framework ImageIO

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>local.adrian.$NAME</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$BUNDLE"

# 4. Package
rm -f "$PACKAGE"
(cd "$BUILD" && ditto -c -k --sequesterRsrc --keepParent "$NAME.component" "$PACKAGE")
echo "$PACKAGE"

# 5. Optional: install directly (./build.sh install)
if [ "${1:-}" = "install" ]; then
  DEST="$HOME/Library/foobar2000-v2/user-components"
  mkdir -p "$DEST"
  rm -rf "$DEST/$NAME.component"
  cp -R "$BUNDLE" "$DEST/"
  echo "Installed to $DEST/$NAME.component – restart foobar2000."
fi
