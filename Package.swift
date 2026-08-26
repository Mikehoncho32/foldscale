// swift-tools-version: 5.10
import PackageDescription

// FoldscaleCore is the Foundation-only engine behind Foldscale — the recursive scanner,
// node model, exclusions, smart lists, persistence, and safe file actions.
// It has ZERO UI dependencies (enforced by GuardrailTests) so it can be unit
// tested in isolation via `swift test`. The SwiftUI app target (FoldscaleApp) lives
// outside this package and is built with xcodegen + xcodebuild (see project.yml).
let package = Package(
    name: "Foldscale",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FoldscaleCore", targets: ["FoldscaleCore"])
    ],
    targets: [
        .target(
            name: "FoldscaleCore"
        ),
        .executableTarget(
            name: "foldscale-bench",
            dependencies: ["FoldscaleCore"]
        ),
        .testTarget(
            name: "FoldscaleCoreTests",
            dependencies: ["FoldscaleCore"]
        )
    ]
)
