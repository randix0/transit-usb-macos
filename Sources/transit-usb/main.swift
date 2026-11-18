// transit-usb — user-space replacement for the legacy M-Audio Transit USB 1.8 kext/prefPane.
// The Transit (VID 0x0763, PID 0x2006) is a USB Audio Class 1.0 device; macOS' built-in
// AppleUSBAudio driver streams audio. This tool covers what the old kext did on top:
// inspecting the descriptors and reading/setting the endpoint sampling-frequency control.
import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

let kVendor = 0x0763
let kProduct = Int(ProcessInfo.processInfo.environment["TRANSIT_PID"] ?? "") ?? 0x2006

struct AltSetting { var iface: Int; var alt: Int; var endpoint: Int; var channels = 0
    var bits = 0; var rates: [Int] = []; var hasFreqControl = false; var isOut: Bool { endpoint & 0x80 == 0 } }

func findDevice() -> io_service_t? {
    let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
    m.setObject(kVendor, forKey: "idVendor" as NSString)
    m.setObject(kProduct, forKey: "idProduct" as NSString)
    let s = IOServiceGetMatchingService(kIOMainPortDefault, m)
    return s == 0 ? nil : s
}

func parse(_ d: [UInt8]) -> [AltSetting] {
    var out: [AltSetting] = [], i = 0, cur: AltSetting? = nil
    func flush() { if let c = cur, c.endpoint != 0 { out.append(c) } }
    while i + 2 <= d.count, d[i] > 0 {
        let len = Int(d[i]), t = d[i+1]; guard i + len <= d.count else { break }
        switch t {
        case 4: flush(); cur = nil
            if d[i+5] == 1 && d[i+6] == 2 { cur = AltSetting(iface: Int(d[i+2]), alt: Int(d[i+3]), endpoint: 0) }
        case 5: if cur != nil { cur!.endpoint = Int(d[i+2]) }
        case 0x24 where cur != nil && len >= 8 && d[i+2] == 2: // FORMAT_TYPE_I
            cur!.channels = Int(d[i+4]); cur!.bits = Int(d[i+6]); let n = Int(d[i+7])
            if n == 0, len >= 14 { cur!.rates = [Int(d[i+8]) | Int(d[i+9]) << 8 | Int(d[i+10]) << 16, Int(d[i+11]) | Int(d[i+12]) << 8 | Int(d[i+13]) << 16] }
            else { for k in 0..<n where i+8+3*k+2 < i+len { let o = i+8+3*k; cur!.rates.append(Int(d[o]) | Int(d[o+1]) << 8 | Int(d[o+2]) << 16) } }
        case 0x25 where cur != nil && len >= 4 && d[i+2] == 1: cur!.hasFreqControl = d[i+3] & 1 != 0
        default: break }
        i += len
    }
    flush(); return out
}

func usage() -> Never {
    print("usage: transit-usb info | get-rate <endpoint-hex> | set-rate <endpoint-hex> <hz>"); exit(2) }

let args = CommandLine.arguments.dropFirst().map { String($0) }
guard let cmd = args.first else { usage() }

// `daemon <firmware>`: watch for a Transit in DFU mode (0763:2806) and load the firmware each time it is plugged in.
if cmd == "daemon" {
    guard args.count >= 2 else { usage() }
    let fwPath = args[1], me = CommandLine.arguments[0]
    func handle(_ it: io_iterator_t) {
        while case let s = IOIteratorNext(it), s != 0 {
            IOObjectRelease(s)
            let p = Process(); p.executableURL = URL(fileURLWithPath: me)
            p.arguments = ["load-firmware", fwPath]
            p.environment = ["TRANSIT_PID": "10246", "TRANSIT_RESET": "1"]
            try? p.run(); p.waitUntilExit()
            print("transit-usb: firmware load exit \(p.terminationStatus)"); fflush(stdout)
        }
    }
    let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
    m.setObject(kVendor, forKey: "idVendor" as NSString); m.setObject(0x2806, forKey: "idProduct" as NSString)
    let port = IONotificationPortCreate(kIOMainPortDefault)
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
    var iter: io_iterator_t = 0
    IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, m, { _, it in
        usleep(300_000)   // let the DFU device settle
        let args = CommandLine.arguments, me = args[0], fw = args[2]
        while case let s = IOIteratorNext(it), s != 0 {
            IOObjectRelease(s)
            let p = Process(); p.executableURL = URL(fileURLWithPath: me); p.arguments = ["load-firmware", fw]
            p.environment = ["TRANSIT_PID": "10246", "TRANSIT_RESET": "1"]
            try? p.run(); p.waitUntilExit()
            print("transit-usb: firmware load exit \(p.terminationStatus)"); fflush(stdout)
        }
    }, nil, &iter)
    handle(iter)   // arms the notification and handles devices already present
    CFRunLoopRun(); exit(0)
}
guard let svc = findDevice() else { print("M-Audio Transit USB (0763:2006) not found."); exit(1) }

do {
    let dev = try IOUSBHostDevice(__ioService: svc, options: [], queue: nil, interestHandler: nil)
    if cmd == "dfu-status" { // read-only DFU_GETSTATUS / DFU_GETSTATE on interface 0
        let d = NSMutableData(length: 6)!; var got = 0
        try dev.__send(IOUSBDeviceRequest(bmRequestType: 0xA1, bRequest: 3, wValue: 0, wIndex: 0, wLength: 6), data: d, bytesTransferred: &got, completionTimeout: 1)
        let b = [UInt8](d as Data); print("DFU status=\(b[0]) pollTimeout=\(Int(b[1]) + Int(b[2]) << 8) state=\(b[4]) (0 appIDLE,1 appDETACH,2 dfuIDLE,5 dfuDNLOAD-IDLE,8 dfuMANIFEST-WAIT-RESET,10 dfuERROR)")
        exit(0)
    }
    if cmd == "load-firmware" { // DFU download of the Windows driver's ma006101.bin into device RAM
        guard args.count >= 2, let fw = FileManager.default.contents(atPath: args[1]) else { usage() }
        func status() throws -> (st: UInt8, state: UInt8, poll: Int) {
            let d = NSMutableData(length: 6)!; var g = 0
            try dev.__send(IOUSBDeviceRequest(bmRequestType: 0xA1, bRequest: 3, wValue: 0, wIndex: 0, wLength: 6), data: d, bytesTransferred: &g, completionTimeout: 1)
            let b = [UInt8](d as Data); return (b[0], b[4], Int(b[1]) + (Int(b[2]) << 8) + (Int(b[3]) << 16))
        }
        func dnload(_ block: UInt16, _ chunk: Data) throws {
            let d = NSMutableData(data: chunk); var g = 0
            try dev.__send(IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: 1, wValue: block, wIndex: 0, wLength: UInt16(chunk.count)), data: d, bytesTransferred: &g, completionTimeout: 2)
            let s = try status(); usleep(UInt32(min(s.poll, 250)) * 1000)
            if s.st != 0 { print("block \(block): DFU status \(s.st) state \(s.state)"); exit(1) }
        }
        func ctl(_ req: UInt8) throws { var g = 0; try dev.__send(IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: req, wValue: 0, wIndex: 0, wLength: 0), data: nil, bytesTransferred: &g, completionTimeout: 1) }
        // Windows (madfu.sys, see USBPcap capture) selects configuration 1 before the first DNLOAD.
        try? dev.__configure(withValue: 1, matchInterfaces: false)
        var st0 = try status(); print("initial DFU state \(st0.state) status \(st0.st)")
        if st0.state == 10 { try ctl(4); st0 = try status(); print("after CLRSTATUS: state \(st0.state) status \(st0.st)") }
        if st0.state != 2 { try ctl(6); st0 = try status(); print("after ABORT: state \(st0.state)") }
        var block: UInt16 = 0, off = 0
        while off < fw.count { let n = min(64, fw.count - off); try dnload(block, fw.subdata(in: off..<off+n)); off += n; block += 1 }
        try dnload(block, Data())               // zero-length block = end of image
        let s = try status(); print("sent \(fw.count) bytes in \(block) blocks; final DFU state \(s.state), status \(s.st)")
        // Windows resets the hub port ~70 ms after the last GETSTATUS (capture: 6.322 -> 6.392).
        if ProcessInfo.processInfo.environment["TRANSIT_RESET"] != nil { usleep(70_000); try? dev.reset() } // off by default: device re-enumerates itself
        exit(0)
    }
    if cmd == "reset" { try dev.reset(); print("bus reset issued"); exit(0) }
    if cmd == "raw" {
        for (name, wv) in [("device", UInt16(0x0100)), ("config", 0x0200)] {
            let d = NSMutableData(length: 512)!; var got = 0
            try dev.__send(IOUSBDeviceRequest(bmRequestType: 0x80, bRequest: 6, wValue: wv, wIndex: 0, wLength: 512), data: d, bytesTransferred: &got, completionTimeout: 1)
            print(name + ":", (d as Data).prefix(got).map { String(format: "%02x", $0) }.joined(separator: " "))
        }
        exit(0)
    }
    guard let cfgPtr = dev.configurationDescriptor else {
        print("Device is open but exposes no configuration descriptor (not configured / needs firmware or is held by another client)."); exit(1) }
    let total = Int(cfgPtr.pointee.wTotalLength)
    let bytes = [UInt8](UnsafeBufferPointer(start: UnsafeRawPointer(cfgPtr).assumingMemoryBound(to: UInt8.self), count: total))
    switch cmd {
    case "info":
        print("Product: \((try? dev.__string(with: Int(dev.deviceDescriptor?.pointee.iProduct ?? 0), languageID: 0x0409)) ?? "?")")
        for a in parse(bytes) {
            print(String(format: "iface %d alt %d  ep 0x%02X %@  %dch %d-bit  rates %@  freqCtl=%@", a.iface, a.alt, a.endpoint,
                         a.isOut ? "OUT" : "IN ", a.channels, a.bits, a.rates.map(String.init).joined(separator: ","), a.hasFreqControl ? "yes" : "no"))
        }
    case "get-rate", "set-rate":
        guard args.count >= 2, let ep = UInt16(args[1].replacingOccurrences(of: "0x", with: ""), radix: 16) else { usage() }
        let data = NSMutableData(length: 3)!; var got = 0
        if cmd == "set-rate" {
            guard args.count >= 3, let hz = Int(args[2]) else { usage() }
            data.replaceBytes(in: NSRange(location: 0, length: 3), withBytes: [UInt8(hz & 255), UInt8(hz >> 8 & 255), UInt8(hz >> 16 & 255)])
            try dev.__send(IOUSBDeviceRequest(bmRequestType: 0x22, bRequest: 0x01, wValue: 0x0100, wIndex: ep, wLength: 3), data: data, bytesTransferred: &got, completionTimeout: 1)
            print("rate set to \(hz) Hz")
        } else {
            try dev.__send(IOUSBDeviceRequest(bmRequestType: 0xA2, bRequest: 0x81, wValue: 0x0100, wIndex: ep, wLength: 3), data: data, bytesTransferred: &got, completionTimeout: 1)
            let b = [UInt8](data as Data)
            let hz: Int = Int(b[0]) + (Int(b[1]) << 8) + (Int(b[2]) << 16)
            print("rate: \(hz) Hz")
        }
    default: usage() }
} catch { print("error: \(error)"); exit(1) }
