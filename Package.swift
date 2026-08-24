// swift-tools-version: 5.10
import PackageDescription

// RadixCore is the Foundation-only engine behind Radix — the recursive scanner,
// node model, exclusions, smart lists, persistence, and safe file actions.
// It has ZERO UI dependencies (enforced by GuardrailTests) so it can be unit
// tested in isolation via `swift test`. The SwiftUI app target (RadixApp) lives
// outside this package and is built with xcodegen + xcodebuild (see project.yml).
let package = Package(
    name: "Radix",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RadixCore", targets: ["RadixCore"])
    ],
    targets: [
        .target(
            name: "RadixCore"
        ),
        .executableTarget(
            name: "radix-bench",
            dependencies: ["RadixCore"]
        ),
        .testTarget(
            name: "RadixCoreTests",
            dependencies: ["RadixCore"]
        )
    ]
)
