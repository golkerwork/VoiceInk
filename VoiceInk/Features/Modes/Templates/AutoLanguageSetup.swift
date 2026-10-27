import Foundation

/// One-time switch to automatic language detection. With a fixed language, Whisper turns speech in any
/// other language into that one, so English came out in Spanish. Auto keeps each dictation in the
/// language it was spoken in.
@MainActor
enum AutoLanguageSetup {
    private static let doneKey = "AutoLanguageSetupDone"
    private static let auto = "auto"

    static func applyIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        let manager = ModeManager.shared
        let models = TranscriptionModelRegistry.models

        func supportsAuto(_ modelKey: String?) -> Bool {
            guard let modelKey,
                let model = TranscriptionModelRegistry.model(forSelectionKey: modelKey, in: models)
            else { return false }
            return model.supportedLanguages[auto] != nil
        }

        for var mode in manager.configurations
        where mode.selectedLanguage != auto && supportsAuto(mode.selectedTranscriptionModelName) {
            mode.selectedLanguage = auto
            manager.updateConfiguration(mode)
        }

        if defaults.string(forKey: "SelectedLanguage") != auto,
            supportsAuto(defaults.string(forKey: "CurrentTranscriptionModel"))
        {
            defaults.set(auto, forKey: "SelectedLanguage")
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }

        defaults.set(true, forKey: doneKey)
    }
}
