import SwiftUI

/// The Radix application entry point.
///
/// Milestone 0 ships an empty window that launches cleanly; the outline view,
/// sidebar, toolbar, and footer arrive in later milestones. Colors and fonts are
/// intentionally never hardcoded so dark mode works for free (handoff §4, rule 10).
@main
struct RadixApp: App {
    var body: some Scene {
        WindowGroup("Radix") {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}
