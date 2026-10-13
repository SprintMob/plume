import Foundation

/// What the models table says about each registered model.
///
/// The rule lives here rather than in the view because it is the one piece of
/// the settings window that can be wrong in a way a person would notice — a
/// model reported as installed that is not, or a switch that looks finished
/// while it downloads. Pure, so it is tested like `FocusRules`.
enum ModelCatalog {
    enum Status: Equatable {
        /// Loaded, and the one the next dictation will use.
        case active
        /// Weights arriving. The fraction is the only part either engine
        /// reports; loading afterwards has no number to show.
        case downloading(Double)
        case loading
        /// On disk, ready to become active without a download.
        case installed
        /// Registered but not downloaded.
        case available
        /// The last switch to this model failed. Cleared by the next attempt.
        case failed
    }

    struct Row: Identifiable, Equatable {
        var id: String { model.id }
        let model: TranscriptionModel
        let status: Status

        /// Only one switch runs at a time, and the model in use is already
        /// here — the same rule the menu bar applies to its own items.
        var isSelectable: Bool {
            switch status {
            case .installed, .available, .failed: return true
            case .active, .downloading, .loading: return false
            }
        }
    }

    /// `isInstalled` is injected so the rule can be tested without touching the
    /// filesystem; the default wakes up `ModelWeights.isInstalled`, which had
    /// no caller before the settings window.
    static func rows(
        models: [TranscriptionModel] = ModelRegistry.shared,
        active: TranscriptionModel?,
        pending: TranscriptionModel? = nil,
        progress: Double? = nil,
        failed: TranscriptionModel? = nil,
        isInstalled: (TranscriptionModel) -> Bool = ModelWeights.isInstalled
    ) -> [Row] {
        models.map { model in
            Row(model: model, status: status(
                of: model,
                active: active,
                pending: pending,
                progress: progress,
                failed: failed,
                isInstalled: isInstalled))
        }
    }

    private static func status(
        of model: TranscriptionModel,
        active: TranscriptionModel?,
        pending: TranscriptionModel?,
        progress: Double?,
        failed: TranscriptionModel?,
        isInstalled: (TranscriptionModel) -> Bool
    ) -> Status {
        // A switch in flight wins over every other reading, including over the
        // outgoing model still being the active one: that is the whole reason
        // the table can show a download without lying about what is loaded.
        if model.id == pending?.id {
            guard let progress, progress < 1 else { return .loading }
            return .downloading(progress)
        }
        if model.id == failed?.id { return .failed }
        if model.id == active?.id { return .active }
        return isInstalled(model) ? .installed : .available
    }

    /// `["en"]` and `["multi"]` are the only two shapes the registry uses.
    static func describeLanguages(_ languages: [String]) -> String {
        if languages == ["multi"] { return "Multilingual" }
        if languages == ["en"] { return "English" }
        return languages.joined(separator: ", ")
    }

    static func describeEngine(_ engine: Engine) -> String {
        switch engine {
        case .whisperKit: return "Whisper"
        case .parakeet: return "Parakeet"
        }
    }
}
