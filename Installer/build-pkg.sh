#!/bin/sh
# Builds build/Transit USB Installer.pkg
set -e
cd "$(dirname "$0")"; ROOT="$(cd .. && pwd)"; OUT="$ROOT/build"
"$ROOT/App/build-app.sh"
ST="$OUT/pkgroot"; rm -rf "$ST" "$OUT/pkgtmp"; mkdir -p "$ST/Applications" "$OUT/pkgtmp"
cp -R "$OUT/Transit USB.app" "$ST/Applications/"
pkgbuild --analyze --root "$ST" "$OUT/pkgtmp/components.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$OUT/pkgtmp/components.plist"
pkgbuild --root "$ST" --component-plist "$OUT/pkgtmp/components.plist" --scripts scripts \
  --identifier com.local.transit-usb.pkg --version 2.0 --install-location / "$OUT/pkgtmp/TransitUSB-component.pkg"
pkgbuild --nopayload --scripts scripts-uninstall --identifier com.local.transit-usb.uninstall --version 2.0 "$OUT/pkgtmp/TransitUSB-uninstall.pkg"
productbuild --distribution distribution.xml --resources resources --package-path "$OUT/pkgtmp" "$OUT/Transit USB Installer.pkg"
rm -rf "$ST" "$OUT/pkgtmp"
echo "Built: $OUT/Transit USB Installer.pkg"
