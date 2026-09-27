// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "slate-bridge-mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BridgeCore", targets: ["BridgeCore"]),
        .library(name: "BridgeWriter", targets: ["BridgeWriter"]),
        .executable(name: "slate-bridge", targets: ["slate-bridge"]),
    ],
    targets: [
        // Records to files. Foundation and CryptoKit only: no EventKit, no
        // Contacts, no file system. Tested against the example vault.
        .target(name: "BridgeCore"),
        // §6.2 and §6.5 against a real folder: the manifest, ownership,
        // following files by uid:, deletion, byte-compared atomic writes.
        .target(name: "BridgeWriter", dependencies: ["BridgeCore"]),
        // One sync into a given folder.
        .executableTarget(name: "slate-bridge", dependencies: ["BridgeCore", "BridgeWriter"]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"]),
        .testTarget(name: "BridgeWriterTests", dependencies: ["BridgeCore", "BridgeWriter"]),
    ]
)
