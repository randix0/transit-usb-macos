import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16",16),("32",32),("64",64),("128",128),("256",256),("512",512),("1024",1024)] {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let p = NSBezierPath(roundedRect: r.insetBy(dx: s*0.06, dy: s*0.06), xRadius: s*0.22, yRadius: s*0.22)
        NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.24, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 1)])!.draw(in: p, angle: -90)
        let cfg = NSImage.SymbolConfiguration(pointSize: s*0.46, weight: .semibold).applying(.init(paletteColors: [NSColor(calibratedRed: 1, green: 0.62, blue: 0.1, alpha: 1)]))
        if let sym = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let sz = sym.size; sym.draw(in: NSRect(x: (s-sz.width)/2, y: (s-sz.height)/2, width: sz.width, height: sz.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
