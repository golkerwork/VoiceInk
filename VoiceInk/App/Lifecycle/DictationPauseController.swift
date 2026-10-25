import Foundation

/// Switches VoiceInk off while the user isn't dictating: the shortcut is ignored, call detection stops,
/// and local AI models are unloaded from memory. Speech models are already released after every dictation.
@MainActor
final class DictationPauseController: ObservableObject {
    static let shared = DictationPauseController()

    @Published private(set) var isPaused = false

    private init() {}

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            unloadLocalAIModels()
        }
    }

    private func unloadLocalAIModels() {
        let defaults = UserDefaults.standard
        var models = Set(
            ModeManager.shared.configurations
                .filter { $0.selectedAIProvider == AIProvider.ollama.rawValue }
                .compactMap(\.selectedAIModel)
        )
        for key in ["ollamaSelectedModel", "OllamaSelectedModel"] {
            if let model = defaults.string(forKey: key) {
                models.insert(model)
            }
        }
        for model in models {
            OllamaWarmup.unload(model: model)
        }
    }
}
