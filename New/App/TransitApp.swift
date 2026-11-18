import SwiftUI
import CoreAudio
import IOKit

// MARK: - Localisation (English / Ukrainian)
func L(_ en: String, _ uk: String) -> String {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("uk") ? uk : en
}

// MARK: - USB state
enum USBState { case missing, dfu, ready }

func usbHas(product: Int) -> Bool {
    let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
    m.setObject(0x0763, forKey: "idVendor" as NSString)
    m.setObject(product, forKey: "idProduct" as NSString)
    let s = IOServiceGetMatchingService(kIOMainPortDefault, m)
    if s != 0 { IOObjectRelease(s); return true }
    return false
}

// MARK: - CoreAudio helpers
func caAddr(_ s: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
            _ e: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: sc, mElement: e)
}

func caArray<T>(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ zero: T) -> [T] {
    var a = a; var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var arr = [T](repeating: zero, count: Int(size) / MemoryLayout<T>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &arr) == noErr else { return [] }
    return arr
}

func caFloat(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope, _ el: UInt32) -> Float32? {
    var a = caAddr(sel, sc, el); guard AudioObjectHasProperty(obj, &a) else { return nil }
    var v: Float32 = 0; var sz = UInt32(4)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v) == noErr ? v : nil
}
func caSetFloat(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope, _ el: UInt32, _ v: Float32) {
    var a = caAddr(sel, sc, el); guard AudioObjectHasProperty(obj, &a) else { return }
    var x = v; AudioObjectSetPropertyData(obj, &a, 0, nil, 4, &x)
}
func caUInt(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope, _ el: UInt32) -> UInt32? {
    var a = caAddr(sel, sc, el); guard AudioObjectHasProperty(obj, &a) else { return nil }
    var v: UInt32 = 0; var sz = UInt32(4)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, &v) == noErr ? v : nil
}
func caSetUInt(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ sc: AudioObjectPropertyScope, _ el: UInt32, _ v: UInt32) {
    var a = caAddr(sel, sc, el); guard AudioObjectHasProperty(obj, &a) else { return }
    var x = v; AudioObjectSetPropertyData(obj, &a, 0, nil, 4, &x)
}

/// One direction (playback or recording) of the Transit as seen by CoreAudio.
struct Endpoint {
    var id: AudioObjectID
    var scope: AudioObjectPropertyScope

    var streams: [AudioObjectID] { caArray(id, caAddr(kAudioDevicePropertyStreams, scope), AudioObjectID(0)) }
    var channels: [UInt32] { [1, 2].filter { caFloat(id, kAudioDevicePropertyVolumeScalar, scope, $0) != nil } }
    var hasVolume: Bool { !channels.isEmpty || caFloat(id, kAudioDevicePropertyVolumeScalar, scope, 0) != nil }
    var volume: Float {
        let v = channels.compactMap { caFloat(id, kAudioDevicePropertyVolumeScalar, scope, $0) }
        if !v.isEmpty { return v.reduce(0, +) / Float(v.count) }
        return caFloat(id, kAudioDevicePropertyVolumeScalar, scope, 0) ?? 0
    }
    func setVolume(_ x: Float) {
        for c in channels { caSetFloat(id, kAudioDevicePropertyVolumeScalar, scope, c, x) }
        if channels.isEmpty { caSetFloat(id, kAudioDevicePropertyVolumeScalar, scope, 0, x) }
    }
    var muteElement: UInt32? { [0, 1].first { caUInt(id, kAudioDevicePropertyMute, scope, $0) != nil } }
    var muted: Bool { muteElement.flatMap { caUInt(id, kAudioDevicePropertyMute, scope, $0) } == 1 }
    func setMute(_ m: Bool) { if let e = muteElement { caSetUInt(id, kAudioDevicePropertyMute, scope, e, m ? 1 : 0) } }

    var rate: Double {
        var a = caAddr(kAudioDevicePropertyNominalSampleRate); var v = Float64(0); var sz = UInt32(8)
        AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &v); return v
    }
    var availableRates: [Double] {
        let r = caArray(id, caAddr(kAudioDevicePropertyAvailableNominalSampleRates), AudioValueRange())
        let std: [Double] = [8000, 11025, 16000, 22050, 32000, 44100, 48000, 88200, 96000]
        var out = Set<Double>()
        for x in r { if x.mMinimum == x.mMaximum { out.insert(x.mMinimum.rounded()) }
            else { std.filter { $0 >= x.mMinimum - 1 && $0 <= x.mMaximum + 1 }.forEach { out.insert($0) } } }
        return out.sorted()
    }
    func setRate(_ r: Double) {
        var a = caAddr(kAudioDevicePropertyNominalSampleRate); var v = r
        AudioObjectSetPropertyData(id, &a, 0, nil, 8, &v)
    }
    var bitDepth: Int? {
        guard let s = streams.first else { return nil }
        var a = caAddr(kAudioStreamPropertyPhysicalFormat); var f = AudioStreamBasicDescription(); var sz = UInt32(MemoryLayout.size(ofValue: f))
        return AudioObjectGetPropertyData(s, &a, 0, nil, &sz, &f) == noErr ? Int(f.mBitsPerChannel) : nil
    }
    var availableBitDepths: [Int] {
        guard let s = streams.first else { return [] }
        let f = caArray(s, caAddr(kAudioStreamPropertyAvailablePhysicalFormats), AudioStreamRangedDescription())
        return Array(Set(f.map { Int($0.mFormat.mBitsPerChannel) })).sorted()
    }
    func setBitDepth(_ bits: Int) {
        guard let s = streams.first else { return }
        let f = caArray(s, caAddr(kAudioStreamPropertyAvailablePhysicalFormats), AudioStreamRangedDescription())
        guard var asbd = f.first(where: { Int($0.mFormat.mBitsPerChannel) == bits })?.mFormat else { return }
        if asbd.mSampleRate == 0 { asbd.mSampleRate = rate }
        var a = caAddr(kAudioStreamPropertyPhysicalFormat)
        AudioObjectSetPropertyData(s, &a, 0, nil, UInt32(MemoryLayout.size(ofValue: asbd)), &asbd)
    }
}

func findEndpoints() -> (out: Endpoint?, inp: Endpoint?) {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    var out: Endpoint?, inp: Endpoint?
    for id in caArray(sys, caAddr(kAudioHardwarePropertyDevices), AudioObjectID(0)) {
        var a = caAddr(kAudioObjectPropertyName); var n: CFString = "" as CFString; var sz = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &n)
        guard (n as String).contains("Transit") else { continue }
        let o = Endpoint(id: id, scope: kAudioObjectPropertyScopeOutput)
        let i = Endpoint(id: id, scope: kAudioObjectPropertyScopeInput)
        if out == nil, !o.streams.isEmpty { out = o }
        if inp == nil, !i.streams.isEmpty { inp = i }
    }
    return (out, inp)
}

// MARK: - Auto-load agent + firmware loader
enum Agent {
    static let label = "com.local.transit-usb"
    static var plistURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var logURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/transit-usb.log") }
    static var helper: String { Bundle.main.bundlePath + "/Contents/Helpers/transit-usb" }
    static var firmware: String { (Bundle.main.resourcePath ?? "") + "/ma006101.bin" }
    static var uid: String { String(getuid()) }

    @discardableResult static func sh(_ args: [String], env: [String: String]? = nil) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: args[0]); p.arguments = Array(args.dropFirst())
        if let env { p.environment = env }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
    }
    static var isEnabled: Bool { sh(["/bin/launchctl", "print", "gui/\(uid)/\(label)"]).0 == 0 }
    static var pointsHere: Bool {
        guard let s = try? String(contentsOf: plistURL) else { return false }
        return s.contains(helper)
    }
    static func enable() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key><array><string>\(helper)</string><string>daemon</string><string>\(firmware)</string></array>
          <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>\(logURL.path)</string><key>StandardErrorPath</key><string>\(logURL.path)</string>
        </dict></plist>
        """
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        sh(["/bin/launchctl", "bootout", "gui/\(uid)/\(label)"])
        sh(["/bin/launchctl", "bootstrap", "gui/\(uid)", plistURL.path])
    }
    static func disable() {
        sh(["/bin/launchctl", "bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }
    static func loadFirmwareNow() -> (Bool, String) {
        let r = sh([helper, "load-firmware", firmware], env: ["TRANSIT_PID": "10246", "TRANSIT_RESET": "1"])
        return (r.0 == 0, r.1)
    }
}

// MARK: - Model
/// Everything the UI shows for one direction. Equatable so the view is only redrawn when something really changed
/// (redrawing every second closed open pop-up menus before a choice could be made).
struct EPState: Equatable {
    var hasVolume = false, volume: Double = 0
    var hasMute = false, muted = false
    var rates: [Double] = [], rate: Double = 0
    var depths: [Int] = [], bits: Int = 0
}

func snapshot(_ e: Endpoint) -> EPState {
    EPState(hasVolume: e.hasVolume, volume: Double(e.volume), hasMute: e.muteElement != nil, muted: e.muted,
            rates: e.availableRates, rate: e.rate, depths: e.availableBitDepths, bits: e.bitDepth ?? 0)
}

@MainActor final class Model: ObservableObject {
    @Published var usb: USBState = .missing
    @Published var outState: EPState?
    @Published var inState: EPState?
    @Published var autoLoad = false
    @Published var busy = false
    @Published var message = ""
    private var out: Endpoint?, inp: Endpoint?
    private var timer: Timer?
    var dragging = false          // a slider is being dragged: do not overwrite it

    init() {
        if Agent.isEnabled && !Agent.pointsHere { Agent.enable() }   // self-heal after the app was moved/updated
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func refresh() {
        let al = Agent.isEnabled; if al != autoLoad { autoLoad = al }
        let u: USBState = usbHas(product: 0x2806) ? .dfu : (usbHas(product: 0x2006) ? .ready : .missing)
        if u != usb { usb = u }
        let e = findEndpoints(); out = e.out; inp = e.inp
        var o = e.out.map(snapshot), i = e.inp.map(snapshot)
        if dragging {
            if let keep = outState?.volume { o?.volume = keep }
            if let keep = inState?.volume { i?.volume = keep }
        }
        if o != outState { outState = o }
        if i != inState { inState = i }
    }
    private func ep(_ isOut: Bool) -> Endpoint? { isOut ? out : inp }
    private func update(_ isOut: Bool, _ f: (inout EPState) -> Void) {
        if isOut { if var s = outState { f(&s); outState = s } } else { if var s = inState { f(&s); inState = s } }
    }
    func setVolume(_ isOut: Bool, _ v: Double) { ep(isOut)?.setVolume(Float(v)); update(isOut) { $0.volume = v } }
    func setMute(_ isOut: Bool, _ m: Bool) { ep(isOut)?.setMute(m); update(isOut) { $0.muted = m } }
    func setRate(_ isOut: Bool, _ r: Double) {
        ep(isOut)?.setRate(r); update(isOut) { $0.rate = r }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.refresh() }
    }
    func setBits(_ isOut: Bool, _ b: Int) {
        ep(isOut)?.setBitDepth(b); update(isOut) { $0.bits = b }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.refresh() }
    }
    func setAutoLoad(_ on: Bool) { on ? Agent.enable() : Agent.disable(); autoLoad = Agent.isEnabled }
    func confirmUninstall() {
        let a = NSAlert(); a.messageText = L("Remove Transit USB?", "Видалити Transit USB?")
        a.informativeText = L("The automatic firmware loader will be turned off and this app moved to the Trash. The Transit will stop working until you install it again.",
                              "Автозавантаження прошивки буде вимкнено, а застосунок переміщено в Кошик. Transit перестане працювати, доки ви не встановите його знову.")
        a.addButton(withTitle: L("Remove", "Видалити")); a.addButton(withTitle: L("Cancel", "Скасувати"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Agent.disable()
        try? FileManager.default.removeItem(at: Agent.logURL)
        NSWorkspace.shared.recycle([URL(fileURLWithPath: Bundle.main.bundlePath)]) { _, _ in NSApp.terminate(nil) }
    }
    func loadFirmware() {
        busy = true; message = L("Loading firmware…", "Завантаження прошивки…")
        Task.detached {
            let r = Agent.loadFirmwareNow()
            await MainActor.run {
                self.busy = false
                self.message = r.0 ? L("Firmware loaded. The device will appear in a few seconds.", "Прошивку завантажено. Пристрій з'явиться за кілька секунд.")
                                   : L("Loading failed: ", "Помилка завантаження: ") + r.1
                self.refresh()
            }
        }
    }
}

// MARK: - UI
struct EndpointSection: View {
    @ObservedObject var m: Model
    let title: String
    let isOut: Bool
    let st: EPState

    var body: some View {
        Section(title) {
            if st.hasVolume {
                HStack {
                    Image(systemName: st.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 22)
                    Slider(value: Binding(get: { st.volume }, set: { m.setVolume(isOut, $0) }), in: 0...1,
                           onEditingChanged: { m.dragging = $0 })
                    Text("\(Int(st.volume * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            if st.hasMute {
                Toggle(L("Mute", "Вимкнути звук"), isOn: Binding(get: { st.muted }, set: { m.setMute(isOut, $0) }))
            }
            if st.rates.count > 1 {
                Picker(L("Sample rate", "Частота дискретизації"), selection: Binding(get: { st.rate }, set: { m.setRate(isOut, $0) })) {
                    ForEach(st.rates, id: \.self) { Text(verbatim: "\(Int($0)) Hz").tag($0) }
                }
            }
            if st.depths.count > 1 {
                Picker(L("Bit depth", "Розрядність"), selection: Binding(get: { st.bits }, set: { m.setBits(isOut, $0) })) {
                    ForEach(st.depths, id: \.self) { Text(verbatim: "\($0) bit").tag($0) }
                }.pickerStyle(.segmented)
            }
        }
    }
}

struct ContentView: View {
    @StateObject var m = Model()

    var statusText: (String, String, Color) {
        switch m.usb {
        case .ready: return ("checkmark.circle.fill", L("Connected and ready", "Підключено і готово до роботи"), .green)
        case .dfu: return ("exclamationmark.triangle.fill", L("Waiting for firmware", "Очікує завантаження прошивки"), .orange)
        case .missing: return ("cable.connector.slash", L("Not connected", "Не підключено"), .secondary)
        }
    }

    var body: some View {
        let st = statusText
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: st.0).font(.system(size: 30)).foregroundColor(st.2)
                    VStack(alignment: .leading) {
                        Text("M-Audio Transit USB").font(.headline)
                        Text(st.1).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if m.usb == .dfu {
                        Button(L("Load firmware", "Завантажити прошивку")) { m.loadFirmware() }.disabled(m.busy)
                    }
                    if m.busy { ProgressView().controlSize(.small) }
                }
                if !m.message.isEmpty { Text(m.message).font(.callout).foregroundStyle(.secondary) }
            }
            if let o = m.outState { EndpointSection(m: m, title: L("Output", "Вихід"), isOut: true, st: o) }
            if let i = m.inState { EndpointSection(m: m, title: L("Input", "Вхід"), isOut: false, st: i) }
            Section(L("Firmware", "Прошивка")) {
                Toggle(L("Load firmware automatically when the device is plugged in", "Завантажувати прошивку автоматично при підключенні"),
                       isOn: Binding(get: { m.autoLoad }, set: m.setAutoLoad))
                Text(L("The Transit loses its firmware whenever it is unplugged. This background helper sends it again, so the device just works.",
                       "Transit втрачає прошивку при кожному відключенні. Фоновий помічник завантажує її знову, тож пристрій просто працює."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("Uninstall…", "Видалити…")) { m.confirmUninstall() }
                    Button(L("Open Sound settings", "Відкрити налаштування звуку")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                    Button(L("Show log", "Показати журнал")) {
                        NSWorkspace.shared.activateFileViewerSelecting([Agent.logURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 640)
    }
}

@main struct TransitSettingsApp: App {
    var body: some Scene {
        Window("Transit USB", id: "main") { ContentView() }
            .windowResizability(.contentSize)
    }
}
