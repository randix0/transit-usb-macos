#!/bin/sh
# Build with Xcode's own toolchain (a swiftly/other swiftc on PATH may not match the SDK).
set -e
cd "$(dirname "$0")"; mkdir -p bin
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
$TC -sdk "$(xcrun --show-sdk-path)" -O Sources/transit-usb/main.swift -o bin/transit-usb -framework IOKit -framework IOUSBHost
