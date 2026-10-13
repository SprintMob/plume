import AppKit
import SwiftUI

/// Every registered model, where it is, and which one the next dictation will
/// use. Picking one downloads it if it has to; the model in use keeps working
/// until the new one has loaded.
struct ModelsSection: View {
    @ObservedObject var state: DaemonState

    /// A `fileExists` per model, taken when the section appears and after each
    /// switch rather than on every redraw — a download re-renders this view
    /// many times a second.
    @State private var installed: Set<String> = []

    private var rows: [ModelCatalog.Row] {
        ModelCatalog.rows(
            active: state.preparation == .ready ? state.model : nil,
            pending: state.pendingModel,
            progress: state.switchProgress,
            failed: state.failedModel,
            isInstalled: { installed.contains($0.id) })
    }

    var body: some View {
        SettingsPage {
            SettingsGroup(
                "Models",
                footnote: "plume keeps the model in use and the one before it, and removes the rest as soon as a switch succeeds. Going back costs nothing, and there is no delete button to get wrong."
            ) {
                header
                ForEach(rows) { row in
                    SettingsDivider()
                    ModelRow(row: row) { state.selectModel(row.model) }
                        .disabled(state.preparation != .ready || state.dictation != .idle)
                }
            }

            SettingsGroup(
                "Dictation examples",
                footnote: "Whisper models only. Parakeet ignores them. Examples teach the decoder how you phrase things, not which words exist: a bare list of terms measures worse than nothing."
            ) {
                SettingsRow(
                    "Example sentences",
                    detail: "A few sentences dictated the way you dictate, per language."
                ) {
                    Button("Edit…") { openExamples() }
                }
            }
        }
        .onAppear(perform: refreshInstalled)
        .onChange(of: state.model.id) { _, _ in refreshInstalled() }
        .onChange(of: state.pendingModel?.id) { _, _ in refreshInstalled() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("Engine").frame(width: 80, alignment: .leading)
            Text("Languages").frame(width: 95, alignment: .leading)
            Text("Size").frame(width: 70, alignment: .trailing)
            Text("Status").frame(width: 130, alignment: .trailing)
        }
        .font(Style.font(Style.Text.caption, .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func refreshInstalled() {
        installed = Set(ModelRegistry.shared.filter(ModelWeights.isInstalled).map(\.id))
    }

    /// Creates the file on first use so the format is explained where it is
    /// edited — the same thing the menu bar item does.
    private func openExamples() {
        do {
            try DictationExamples.ensureFileExists()
            NSWorkspace.shared.open(DictationExamples.file)
        } catch {
            FileHandle.standardError.write(Data("could not open dictation example: \(error)\n".utf8))
        }
    }
}

private struct ModelRow: View {
    let row: ModelCatalog.Row
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Style.Space.x3) {
                HStack(spacing: Style.Space.x2) {
                    Text(row.model.displayName)
                        .font(Style.font(Style.Text.body, .medium))
                    if row.model.recommended {
                        // Was a lime star, which is 1.13:1 on a light window,
                        // so in the light appearance it was simply not there.
                        // A capsule uses lime the only way lime works, as a
                        // fill, and the word says what the star was hoping to.
                        Text("Recommended")
                            .font(Style.font(Style.Text.caption, .semibold))
                            .foregroundStyle(Style.onLime)
                            .padding(.horizontal, Style.Space.x2)
                            .padding(.vertical, 1)
                            .background(Style.lime, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(ModelCatalog.describeEngine(row.model.engine))
                    .frame(width: 80, alignment: .leading)
                Text(ModelCatalog.describeLanguages(row.model.languages))
                    .frame(width: 95, alignment: .leading)
                Text("\(row.model.sizeMB) MB")
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
                ModelStatusLabel(status: row.status)
                    .frame(width: 130, alignment: .trailing)
            }
            .font(Style.font(Style.Text.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Style.Space.x4)
            .padding(.vertical, Style.Space.x3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.isSelectable)
        .help(row.isSelectable ? "Switch to \(row.model.displayName)" : "")
    }
}

private struct ModelStatusLabel: View {
    let status: ModelCatalog.Status

    var body: some View {
        switch status {
        case .active:
            // A status, and lime does not carry status. The weight does.
            Text("Active")
                .font(Style.font(Style.Text.caption, .semibold))
                .foregroundStyle(.primary)
        case .downloading(let fraction):
            HStack(spacing: Style.Space.x2) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 64)
                Text("\(Int(fraction * 100))%")
                    .font(Style.font(Style.Text.caption))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .loading:
            HStack(spacing: Style.Space.x2) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Loading").font(Style.font(Style.Text.caption)).foregroundStyle(.secondary)
            }
        case .installed:
            Text("Downloaded")
                .font(Style.font(Style.Text.caption))
                .foregroundStyle(.secondary)
        case .available:
            HStack(spacing: Style.Space.x1) {
                Image(systemName: "arrow.down.circle").font(Style.font(Style.Text.caption))
                Text("Download").font(Style.font(Style.Text.caption))
            }
            .foregroundStyle(.tertiary)
        case .failed:
            Text("Failed")
                .font(Style.font(Style.Text.caption, .semibold))
                .foregroundStyle(.red)
        }
    }
}
