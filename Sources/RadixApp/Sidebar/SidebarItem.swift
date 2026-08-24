import SwiftUI

/// Sidebar destinations: the scanned folder and the smart lists — places you go,
/// not features you toggle (handoff §4, rule 5).
enum SidebarItem: Hashable, Identifiable, CaseIterable {
    case folder
    case largeFiles
    case oldAndBig

    var id: Self { self }

    var title: String {
        switch self {
        case .folder: return "Folder"
        case .largeFiles: return "Large files"
        case .oldAndBig: return "Old and big"
        }
    }

    var systemImage: String {
        switch self {
        case .folder: return "folder"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .oldAndBig: return "clock.arrow.circlepath"
        }
    }

    var isSmartList: Bool { self != .folder }
}
