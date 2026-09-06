import Foundation

/// The dictations of the current daemon run, newest first, in memory only.
///
/// Nothing here reaches disk. The buffer is capped, it is emptied when the
/// daemon restarts, and `SettingsStore.sessionHistory` turns it off entirely —
/// which is what keeps the README's promise that transcripts are never written
/// to disk literally true. See ADR-0007.
@MainActor
final class TranscriptHistory: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        /// Empty when the recording held no speech. The section renders that
        /// case rather than dropping it: a dictation that produced nothing is
        /// still something the user did and wants explained.
        let text: String
        let at: Date
        /// How long transcription took, which is the only per-dictation
        /// measurement the daemon already computes.
        let latency: TimeInterval

        init(id: UUID = UUID(), text: String, at: Date, latency: TimeInterval) {
            self.id = id
            self.text = text
            self.at = at
            self.latency = latency
        }
    }

    /// One day's worth of entries, as the section lists them.
    struct Day: Identifiable, Equatable {
        /// Days before today. Stable within a listing, which is all a
        /// `ForEach` needs.
        let id: Int
        let label: String
        let entries: [Entry]
    }

    @Published private(set) var entries: [Entry] = []

    /// Far more than a day of heavy dictation, and small enough that the
    /// buffer never becomes a reason the daemon grows.
    let capacity: Int

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    func record(_ text: String, latency: TimeInterval, at: Date = Date()) {
        entries.insert(Entry(text: text, at: at, latency: latency), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Groups newest-first entries by calendar day, labelled the way the
    /// section heads them. `calendar` and `now` are arguments rather than
    /// `.current` and `Date()` so the labels can be tested without waiting for
    /// midnight.
    static func grouped(
        _ entries: [Entry],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var order: [Int] = []
        var byOffset: [Int: [Entry]] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.at)
            let offset = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            if byOffset[offset] == nil {
                order.append(offset)
            }
            byOffset[offset, default: []].append(entry)
        }

        return order.map { offset in
            Day(id: offset, label: label(daysAgo: offset), entries: byOffset[offset] ?? [])
        }
    }

    private static func label(daysAgo offset: Int) -> String {
        switch offset {
        case ..<0: return "Later"
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(offset) days ago"
        }
    }

    /// Case- and accent-insensitive, so searching `reglement` finds
    /// `règlement`. An empty query matches everything rather than nothing.
    static func filtered(_ entries: [Entry], query: String) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
