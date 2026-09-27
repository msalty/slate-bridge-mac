// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "slate-bridge-mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
    ],
    targets: [
        // Records to files. Foundation and CryptoKit only: no EventKit, no
        // Contacts, no file system. Tested against the example vault.
        .target(name: "BridgeCore"),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"]),
    ]
)
