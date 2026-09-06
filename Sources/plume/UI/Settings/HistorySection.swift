import SwiftUI

/// What has been dictated since the daemon started.
///
/// The one place a transcript outlives its dictation — and it does so in RAM,
/// capped, and only while plume runs. Nothing here reaches disk, which is what
/// keeps the README's promise true. See ADR-0007.
struct HistorySection: View {
    @ObservedObject var state: DaemonState
    @ObservedObject var history: TranscriptHistory

    @State private var query = ""
    @State private var copied: UUID?

    private var days: [TranscriptHistory.Day] {
        TranscriptHistory.grouped(TranscriptHistory.filtered(history.entries, query: query))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !history.entries.isEmpty {
                Button("Clear") {
                    history.clear()
                    query = ""
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .help("Forget every dictation in this session")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if !state.sessionHistoryEnabled {
            notice(
                symbol: "eye.slash",
                title: "Session history is off",
                detail: "Nothing is being kept. Turn it back on under Configuration → Application."
            )
        } else if history.entries.isEmpty {
            notice(
                symbol: "text.quote",
                title: "Nothing yet",
                detail: "Dictations show up here as you make them, and are gone the next time plume starts."
            )
        } else if days.isEmpty {
            notice(
                symbol: "magnifyingglass",
                title: "No match",
                detail: "Nothing in this session contains “\(query)”."
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                banner
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(day.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                        ForEach(day.entries) { entry in
                            EntryCard(entry: entry, copied: copied == entry.id) {
                                TextInjector.copyToPasteboard(entry.text)
                                copied = entry.id
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    /// Stated where the transcripts are, not buried in a settings row: it is
    /// the whole reason this section is allowed to exist.
    private var banner: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(Style.accent)
            Text("Kept in memory only. Cleared when plume restarts, never written to disk.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func notice(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct EntryCard: View {
    let entry: TranscriptHistory.Entry
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .top, spacing: 10) {
                if entry.text.isEmpty {
                    Text("No speech found in this dictation")
                        .font(.system(size: 13).italic())
                        .foregroundStyle(.tertiary)
                } else {
                    Text(entry.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(copied ? "Copied" : "")
                    .font(.system(size: 11))
                    .foregroundStyle(Style.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry.text.isEmpty)
        .help(entry.text.isEmpty ? "" : "Copy to the pasteboard")
    }
}
