import RadixCore
import SwiftUI

/// Placeholder landing view for the Milestone 0 skeleton.
///
/// This is deliberately minimal: it proves the app launches and that RadixApp can
/// link against RadixCore. The Finder-style layout (sidebar · outline · footer)
/// replaces it in Milestone 2.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Radix")
                .font(.largeTitle.weight(.semibold))
            Text("Finder-native disk space analyzer")
                .foregroundStyle(.secondary)
            Text("RadixCore \(RadixCore.version)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 720, minHeight: 460)
        .padding()
    }
}

#Preview {
    ContentView()
}
