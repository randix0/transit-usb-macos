#!/bin/sh
# Installs the Transit firmware auto-loader as a per-user LaunchAgent (no kext, no root needed).
set -e
cd "$(dirname "$0")"
./build.sh
D="$HOME/Library/Application Support/TransitUSB"
mkdir -p "$D" "$HOME/Library/LaunchAgents"
cp bin/transit-usb firmware/ma006101.bin "$D/"
codesign -s - -f "$D/transit-usb" 2>/dev/null || true
cat > "$HOME/Library/LaunchAgents/com.local.transit-usb.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.transit-usb</string>
  <key>ProgramArguments</key><array>
    <string>$D/transit-usb</string><string>daemon</string><string>$D/ma006101.bin</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/transit-usb.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/transit-usb.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/com.local.transit-usb" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.local.transit-usb.plist"
echo "Installed. Replug the Transit; log: ~/Library/Logs/transit-usb.log"
