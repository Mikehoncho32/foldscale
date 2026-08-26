import Foundation

/// Pure, Foundation-only display formatting shared by the UI (and, later, a
/// menu-bar mode). It lives in FoldscaleCore — not the app — so it stays unit-testable
/// and reusable; it imports no UI framework.
public enum DisplayFormat {
    /// A human-readable byte size in Finder's base-10 convention (e.g. "142.3 GB").
    public static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    /// A grouped integer (e.g. "812,404"), respecting the user's locale.
    public static func itemCount(_ value: Int64) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A Finder-style "Modified" label: Today / Yesterday / "Nd ago" (2–6 days) /
    /// a short date. `now` is injectable so the bucketing is deterministic in tests.
    public static func relativeModified(epochSeconds: Int64, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let calendar = Calendar.current
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
            ).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days)d ago"
        default: return shortDateFormatter.string(from: date)
        }
    }

    /// A short month-and-day label ("Aug 19"), in the user's locale.
    public static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = .useAll
        return formatter
    }()

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
