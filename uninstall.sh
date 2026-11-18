#!/bin/sh
launchctl bootout "gui/$(id -u)/com.local.transit-usb" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.local.transit-usb.plist"
rm -rf "$HOME/Library/Application Support/TransitUSB" "$HOME/Library/Logs/transit-usb.log"
echo "Removed."
