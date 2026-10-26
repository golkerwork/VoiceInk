import Foundation
import NaturalLanguage

/// Small local models sometimes translate while cleaning up, even when the prompt says to keep the
/// language. For the built-in cleanup prompts, keep the original text when the cleanup switched language.
enum CleanupLanguageGuard {
    private static let cleanupPromptIds: Set<UUID> = [
        PromptTemplates.defaultPromptId,
        PromptTemplates.chatPromptId,
    ]
    private static let minimumConfidence = 0.8

    static func resolvedText(original: String, cleaned: String, promptId: UUID?) -> String {
        guard let promptId, cleanupPromptIds.contains(promptId),
            let originalLanguage = dominantLanguage(of: original),
            let cleanedLanguage = dominantLanguage(of: cleaned),
            originalLanguage != cleanedLanguage
        else { return cleaned }
        return original
    }

    private static func dominantLanguage(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let top = recognizer.languageHypotheses(withMaximum: 1).first,
            top.value >= minimumConfidence
        else { return nil }
        return top.key
    }
}
