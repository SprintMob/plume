import SwiftUI

/// What plume is doing, and whether it can do it at all.
///
/// The checks are `DoctorReport.run`, the same six the CLI prints, so there
/// is one answer to "is this set up", whichever way you ask.
struct HomeSection: View {
    @ObservedObject var state: DaemonState

    @State private var checks: [Check] = []
    @State private var checking = false

    var body: some View {
        SettingsPage {
            summary
            setup
        }
        .onAppear(perform: recheck)
        .onChange(of: state.hotkey) { _, _ in recheck() }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(alignment: .top, spacing: 0) {
            summaryItem("Status", value: statusText)
            Divider().frame(height: 34)
            summaryItem("Model", value: modelText)
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: Style.Space.x1) {
                HotkeyCaps(hotkey: state.hotkey)
                Text("Hold to dictate")
                    .font(Style.font(Style.Text.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Style.Space.x5)
        }
        .padding(.vertical, Style.Space.x4)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: Style.Radius.btn)
        )
    }

    private func summaryItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Style.Space.x1) {
            Text(value)
                .font(Style.font(Style.Text.title, .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(label)
                .font(Style.font(Style.Text.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Style.Space.x5)
    }

    private var statusText: String {
        switch state.dictation {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .locked: return "Recording · locked"
        case .transcribing: return "Transcribing"
        }
    }

    private var modelText: String {
        if let pending = state.pendingModel {
            guard let fraction = state.switchProgress, fraction < 1 else {
                return "Loading \(pending.displayName)"
            }
            return "\(Int(fraction * 100))% of \(pending.displayName)"
        }
        return state.model.displayName
    }

    // MARK: - Setup

    private var setup: some View {
        SettingsGroup("Setup") {
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                if index > 0 { SettingsDivider() }
                CheckRow(check: check, onPurgeLegacyLogs: purgeLegacyLogs)
            }
            if !checks.isEmpty { SettingsDivider() }
            HStack {
                if checking {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Spacer()
                Button("Check again", action: recheck)
                    .disabled(checking)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    /// Two of the six checks shell out — accessibility reads `ps`, the Fn
    /// mapping reads `defaults` — so they run off the main thread rather than
    /// stalling the window on a section change.
    private func recheck() {
        guard !checking else { return }
        checking = true
        let hotkey = state.hotkey
        Task.detached {
            let result = DoctorReport.run(hotkey: hotkey)
            await MainActor.run {
                checks = result
                checking = false
            }
        }
    }

    private func purgeLegacyLogs() {
        _ = Install.purgeLegacyLogFiles()
        recheck()
    }
}

private struct CheckRow: View {
    let check: Check
    let onPurgeLegacyLogs: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Style.Space.x2) {
            Image(systemName: symbol)
                .font(Style.font(Style.Glyph.md, .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Style.Space.x1) {
                Text(headline)
                    .font(Style.font(Style.Text.body, .medium))
                if let remediation = check.remediation {
                    Text(remediation)
                        .font(Style.font(Style.Text.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Style.Space.x3)
            // The one remediation plume can carry out itself.
            if check.name == "legacy logs", isTrouble {
                Button("Remove them", action: onPurgeLegacyLogs)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var headline: String {
        switch check.status {
        case .ok: return check.name
        case .warn(let detail), .fail(let detail): return "\(check.name): \(detail)"
        }
    }

    private var symbol: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch check.status {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }

    private var isTrouble: Bool {
        if case .ok = check.status { return false }
        return true
    }
}
