# M-Audio Transit USB 1.8.0 — reverse-engineering notes

Source: `legacy-drivers/M-Audio Transit USB.pkg` (Sep 2009). Payload: `MAudioTransitUSBJag.kext` (ppc/i386/x86_64),
`TransitUSBCS` config daemon (StartupItem), prefPane, firmware loader.

## Findings
- Device: USB VID 0x0763 / PID 0x2006. The firmware loader contains **no Transit firmware**
  (only MIDISPORT images) — the device needs no firmware upload.
- Kext class tree: `MaudioUsbTransitUserClientDevice` (IOUSBDevice nub) -> Device/Engine/Stream
  (IOAudioFamily) -> per-endpoint `Interface{Adaptive,Async,Virt,Ac3}{Read,Write}` isoc handlers.
- Protocol is **standard USB Audio Class 1.0** (no vendor requests found):
  - Get rate: bmRequestType 0xA2, bRequest 0x81 (GET_CUR), wValue 0x0100 (SAMPLING_FREQ_CONTROL), wIndex = endpoint, len 3
  - Set rate: bmRequestType 0x22, bRequest 0x01 (SET_CUR), same wValue/wIndex, len 3 (24-bit LE Hz)
  - Formats chosen by alternate setting of the AudioStreaming interfaces; audio over isochronous (adaptive) endpoints.
- Extras the kext added over Apple's class driver: bit depth (16/24), latency setting, AC-3 passthrough
  output, per-channel volume/mute/link, input extra gain. Stored in `PreferenceData`
  (Interface[2]{enabled,available,isOutputAc3}, volume[5], mute[2], linked[2], inputExtraGain, bitDepth, latency).
- Log strings: underrun reset logic ("Too many USB underruns, must reset").

## Why there is no new kext
Kernel extensions cannot be loaded on Apple Silicon without reduced security, and the device is UAC1-compliant,
so macOS' built-in AppleUSBAudio driver already provides audio. Bit depth/rate are set in Audio MIDI Setup.
A DriverKit rewrite would need Apple entitlements and brings no capability the built-in driver lacks.

## What is provided
`transit-usb` (Swift, IOUSBHost): `info` (descriptor dump), `get-rate`/`set-rate <endpoint>`.
Build: `./build.sh`. **Untested against hardware** — no Transit was attached; only compiled and
run for the "not found" path. Request layout is taken from the kext disassembly.

## Removing the legacy install (macOS <= 10.x leftovers)
/System/Library/Extensions/MAudioTransitUSB*.kext, /Library/PreferencePanes/MAudioTransitUSB.prefPane,
/Library/StartupItems/MAudioTransitUSB, "M-Audio Firmware Loader".

## Correction: the device enumerates in DFU (boot) mode first — firmware IS required
Observed on real hardware (macOS 27, Apple Silicon): device appears as **0763:2806**, bDeviceClass 0xFE/01 (DFU),
one config, interface 0 = FE/01/00 with DFU functional descriptor (bmAttributes 0x05 = download + manifestation-tolerant,
wTransferSize 64). `dfu-status`: status OK, state **dfuIDLE** — it is waiting for a firmware download; after that it
re-enumerates as 0763:2006 (UAC1, see above). The 1.8.0 package does not contain the firmware image (the Jag kext's big
data section is vtables; the loader only has MIDISPORT images). The old `MAudioTransitUSBBoot.kext` ("MaudioUsbTransitBootDriver")
that the preflight script deletes held the loader logic; the image must come from an older Transit driver (Mac boot kext or Windows driver).
Tool: `TRANSIT_PID=10246 ./bin/transit-usb dfu-status|raw`.

## Transit_OSX_1.5.8f2_Bld101.dmg (2004) — also contains no Transit firmware
Separate `FirmwareLoader.pkg` (MIDISPORT/etc. images only, no "Transit" string) and `MAudioTransitUSBBoot.kext`
(PPC-only, 30 KB, 1.5 KB const; matches 0763:2006, not 0x2806; no DFU code, no firmware blob). The Transit firmware is
therefore not host-loaded by any M-Audio Mac package; 0763:2806/dfuIDLE is likely a recovery/blank-flash state.

## Firmware found: Transit_6_0_1_5_10_0_5131.exe (Windows driver 6.0.1)
InstallShield wrapper -> MSI32 resource -> Installer.cab -> `DfuBIN` = `ma006101.bin` (5803 B, sha256 978942744c0c…d9b4),
installed by `DfuINF` for `USB\VID_0763&PID_2806` (FirmwareFile=ma006101.bin, MaximumTransferSize 4096). Image = 8051 code with
a header (`27 12 34`, VID 0763, PID 2006, ver 0101). Copy: `firmware/ma006101.bin`.
Protocol (per Windows INF + Linux madfuload): DFU on interface 0, 64-byte DNLOAD blocks (wValue = block no.), GETSTATUS
after each, zero-length DNLOAD, GETSTATUS, bus reset -> re-enumerates as 0763:2006. RAM-only; lost at power-off.
Tool: `TRANSIT_PID=10246 ./bin/transit-usb load-firmware firmware/ma006101.bin`.
First run: 91 blocks accepted (status 0), final state 7 (manifest); device then vanished from the bus and did not reappear
until a physical replug was tried (see session).

## Firmware load experiments (Apple Silicon, macOS 27)
- `DfuSYS` (Windows madfu.sys 1.0.0.22) confirms the sequence: 64-byte DNLOAD blocks, block counter from 0, GETSTATUS after
  each block, delay = **third byte** of bwPollTimeout in ms, zero-length DNLOAD + GETSTATUS at the end. Matches our loader.
- Device accepts all 91 blocks (status 0) and enters DFU state 7 (manifest), then **stays there until a bus reset**; no
  re-enumeration by itself. Stale `dfuERROR` (state 10) from an earlier attempt must be cleared with CLRSTATUS first (done in tool).
- After `IOUSBHostDevice.reset()` (or the library reset failing with 0xE00002C0) the device disappears from the bus and
  nothing new enumerates (no 0763:2006, no other device) — root cause unknown (kernel USB logs not readable here).
  Replug returns it to 0763:2806 (firmware is RAM-only).
Note: in zsh `log` is a builtin; use /usr/bin/log.

## Kernel log of the firmware load (usb-kernel.log)
- Load alone: device stays attached in DFU state 7 indefinitely; no disconnect, no self re-enumeration (so the earlier
  "device vanished" was caused by our reset call).
- `IOUSBHostDevice.reset()` => "terminateDevice: destroying 0763/2806: reset API call", then ~1.1 s later the port goes
  inactive (USB2 data rate None) — the device drops off the bus — and **never reconnects** (no enumerate event).
- Not a port/cable issue (tried two ports, adapter). Hypotheses: bus-power brown-out when the firmware starts, firmware needs a
  hub/other host behaviour, or macOS reset semantics differ from Linux usb_reset(). Next checks: powered USB hub; same driver on Windows.

## Behind a powered hub (usb-kernel2.log) — progress: the device re-attaches
After firmware load + reset the device DOES reconnect to the hub port (so power was not the problem), but enumeration fails
on every retry (~3 s apart):
`AppleUSBXHCICommandRing::setAddress: completed with result code 25` -> `createDevice: failed (0xe00002bc)` ->
`resetAndCreateDevice: failed to address device, disabling port`.
I.e. the firmware-running Transit does not answer SET_ADDRESS on Apple's xHCI (host-side "Address Device" scheme / timing
intolerance of the 2009 8051 firmware). Cannot be fixed from user space. Directly on the Mac port the device just never attached.
Ideas: older/full-speed-only hub, USB-2 hub without TT, Linux/Windows host (old-scheme enumeration), or an Intel Mac with EHCI-less path.

## Windows control test
Same device + Windows driver 6.0.1 (firmware ma006101.bin via DfuSYS): works, audio plays. So the hardware and firmware image are fine;
the failure on the Apple Silicon Mac is host-side enumeration (xHCI SET_ADDRESS timeout after firmware start).

## USBPcap capture of the working Windows 7 flow (legacy-drivers/transit.pcapng, transit_2.pcapng)
DFU device 0763:2806 (bcdUSB 1.00, class FE/01, EP0 max packet 64) -> SET_CONFIGURATION(1) -> 91x DFU_DNLOAD (wValue = block 0..0x5a,
64 B each, 0x2b B last) with GETSTATUS after every block (state 5) -> zero-length DNLOAD block 0x5b -> GETSTATUS =
`00 00 00 20 07 00` (OK, poll timeout 3rd byte 0x20, state 7 = manifest).
Then ~70 ms later, on the **root hub port**: CLEAR_FEATURE PORT_ENABLE, GET_PORT_STATUS (0x0101 = connected, powered, disabled),
~120 ms later SET_FEATURE PORT_RESET -> status 0x0103 + C_RESET -> CLEAR_FEATURE C_PORT_RESET, and **a second PORT_RESET 40 ms later**
(same sequence). Device stays connected and comes back as 0763:2006 (bcdUSB 1.10, EP0 max packet 8, 494-byte config descriptor,
iProduct "Transit USB") ~110 ms after the second reset (t2). Device never drops off the bus on Windows.
Difference vs macOS: macOS issues a single reset via IOUSBHostDevice.reset() (device object destroyed, port re-created) after ~1 s idle in manifest.

## RESULT: working on macOS 27 / Apple Silicon
With SET_CONFIGURATION(1) before the download and a reset 70 ms after the last GETSTATUS (as in the Windows capture), the device
enumerates as 0763:2006 "Transit USB" and macOS' built-in AppleUSBAudio exposes 2 in / 2 out @ 48 kHz. The firmware is RAM-only, so
`install.sh` sets up a LaunchAgent (`transit-usb daemon`) that loads it every time a 0763:2806 device appears.

## Settings app + installer
`App/TransitApp.swift`: SwiftUI app (status, output/input volume & mute, sample rate, bit depth via CoreAudio; firmware auto-load
toggle; uninstall). Helper `transit-usb` + firmware are embedded in the bundle. `Installer/build-pkg.sh` produces an unsigned
distribution .pkg (en/uk) whose postinstall registers the LaunchAgent for the console user.
