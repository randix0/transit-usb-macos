#!/bin/sh
# Builds "Transit USB.app" (universal) with the firmware loader helper and firmware embedded.
set -e
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
SDK="$(xcrun --show-sdk-path)"
OUT="$ROOT/build"; APP="$OUT/Transit USB.app"
rm -rf "$APP" "$OUT/tmp"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$OUT/tmp"

for ARCH in arm64 x86_64; do
  $SWIFTC -sdk "$SDK" -target $ARCH-apple-macos13.0 -parse-as-library -O TransitApp.swift -o "$OUT/tmp/app-$ARCH"
  $SWIFTC -sdk "$SDK" -target $ARCH-apple-macos13.0 -O "$ROOT/Sources/transit-usb/main.swift" -o "$OUT/tmp/helper-$ARCH" -framework IOKit -framework IOUSBHost
done
lipo -create "$OUT"/tmp/app-* -output "$APP/Contents/MacOS/TransitUSB"
lipo -create "$OUT"/tmp/helper-* -output "$APP/Contents/Helpers/transit-usb"
cp "$ROOT/firmware/ma006101.bin" "$APP/Contents/Resources/"

# icon
$SWIFTC -sdk "$SDK" make-icon.swift -o "$OUT/tmp/make-icon" && "$OUT/tmp/make-icon" "$OUT/tmp/icons"
IS="$OUT/tmp/AppIcon.iconset"; mkdir -p "$IS"
cp "$OUT/tmp/icons/16.png" "$IS/icon_16x16.png";   cp "$OUT/tmp/icons/32.png" "$IS/icon_16x16@2x.png"
cp "$OUT/tmp/icons/32.png" "$IS/icon_32x32.png";   cp "$OUT/tmp/icons/64.png" "$IS/icon_32x32@2x.png"
cp "$OUT/tmp/icons/128.png" "$IS/icon_128x128.png"; cp "$OUT/tmp/icons/256.png" "$IS/icon_128x128@2x.png"
cp "$OUT/tmp/icons/256.png" "$IS/icon_256x256.png"; cp "$OUT/tmp/icons/512.png" "$IS/icon_256x256@2x.png"
cp "$OUT/tmp/icons/512.png" "$IS/icon_512x512.png"; cp "$OUT/tmp/icons/1024.png" "$IS/icon_512x512@2x.png"
iconutil -c icns "$IS" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Transit USB</string>
  <key>CFBundleDisplayName</key><string>Transit USB</string>
  <key>CFBundleIdentifier</key><string>com.local.transit-usb.settings</string>
  <key>CFBundleExecutable</key><string>TransitUSB</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>uk</string></array>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict></plist>
PL
codesign -s - -f --deep "$APP"
rm -rf "$OUT/tmp"
echo "Built: $APP"
