// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacToys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacToys", targets: ["MacToys"]),
        .library(name: "MacToysCore", targets: ["MacToysCore"]),
    ],
    targets: [
        // Pure, dependency-free logic. No AppKit, no system permissions -> unit testable.
        .target(name: "MacToysCore"),
        // The actual menu-bar application.
        .executableTarget(name: "MacToys", dependencies: ["MacToysCore"]),
        // Test runner. XCTest does not ship with Command Line Tools, so the suite
        // is a plain executable that exits non-zero on failure.
        .executableTarget(name: "MacToysSelfTest", dependencies: ["MacToysCore"]),
    ]
)
