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
            active: state.model,
            pending: state.pendingModel,
            progress: state.switchProgress,
            failed: state.failedModel,
            isInstalled: { installed.contains($0.id) })
    }

    var body: some View {
        SettingsPage {
            SettingsGroup(
                "Models",
                footnote: "parrot keeps the model in use and the one before it, and removes the rest as soon as a switch succeeds — so going back costs nothing and there is no delete button to get wrong."
            ) {
                header
                ForEach(rows) { row in
                    SettingsDivider()
                    ModelRow(row: row) { state.selectModel(row.model) }
                }
            }

            SettingsGroup(
                "Dictation examples",
                footnote: "Whisper models only — Parakeet ignores them. Examples teach the decoder how you phrase things, not which words exist: a bare list of terms measures worse than nothing."
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
        .font(.system(size: 11, weight: .medium))
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
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    if row.model.recommended {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Style.accent)
                            .help("Recommended")
                    }
                    Text(row.model.displayName)
                        .font(.system(size: 13, weight: .medium))
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
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
            Text("Active")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Style.accent)
        case .downloading(let fraction):
            HStack(spacing: 6) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 64)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Loading").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .installed:
            Text("Downloaded")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .available:
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle").font(.system(size: 11))
                Text("Download").font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
        case .failed:
            Text("Failed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
        }
    }
}
