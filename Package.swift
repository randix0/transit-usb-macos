// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "transit-usb",
    platforms: [.macOS(.v12)],
    targets: [.executableTarget(name: "transit-usb", path: "Sources/transit-usb")]
)
