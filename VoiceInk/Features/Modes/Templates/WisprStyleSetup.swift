import Foundation

/// One-time setup that makes dictation behave like Wispr Flow once the installer has set up a local
/// Ollama model: the default mode cleans up what you say, and messaging apps get a casual texting style.
@MainActor
enum WisprStyleSetup {
    private static let doneKey = "WisprStyleSetupDone"
    static let textingModeID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    static func applyIfNeeded(enhancementService: AIEnhancementService, aiService: AIService) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey),
            defaults.bool(forKey: OnboardingSettings.completedV2Key),
            aiService.selectedProvider == .ollama
        else { return }

        let manager = ModeManager.shared
        guard let defaultMode = manager.configurations.first(where: \.isDefault) else { return }
        let modelName = aiService.currentModel

        var prompts = enhancementService.customPrompts
        for promptID in [PromptTemplates.defaultPromptId, PromptTemplates.chatPromptId]
        where !prompts.contains(where: { $0.id == promptID }) {
            if let seedPrompt = PromptTemplates.seedPrompts.first(where: { $0.id == promptID }) {
                prompts.append(seedPrompt)
            }
        }
        if prompts != enhancementService.customPrompts {
            enhancementService.customPrompts = prompts
        }

        var cleanupMode = defaultMode
        cleanupMode.isAIEnhancementEnabled = true
        cleanupMode.selectedPrompt = PromptTemplates.defaultPromptId.uuidString
        cleanupMode.selectedAIProvider = AIProvider.ollama.rawValue
        cleanupMode.selectedAIModel = modelName
        manager.updateConfiguration(cleanupMode)

        if !manager.configurations.contains(where: { $0.id == textingModeID }),
            let chatTemplate = TriggerTemplateCatalog.templates.first(where: { $0.id == "chat" })
        {
            let messagingApps = chatTemplate.availableGroup(
                installedApps: InstalledApps.load(),
                existingAppBundleIds: [],
                existingWebsites: [],
                cleanURL: manager.cleanURL
            )
            let textingMode = ModeConfig(
                id: textingModeID,
                name: "Texting",
                icon: .symbol("message.fill"),
                triggerGroups: messagingApps.isEmpty ? nil : [messagingApps],
                isAIEnhancementEnabled: true,
                selectedPrompt: PromptTemplates.chatPromptId.uuidString,
                selectedTranscriptionModelName: defaultMode.selectedTranscriptionModelName,
                isRealtimeTranscriptionEnabled: defaultMode.isRealtimeTranscriptionEnabled,
                selectedLanguage: defaultMode.selectedLanguage,
                useSelectedTextContext: false,
                isTextFormattingEnabled: true,
                selectedAIProvider: AIProvider.ollama.rawValue,
                selectedAIModel: modelName
            )
            manager.addConfiguration(textingMode)
        }

        defaults.set(true, forKey: doneKey)
    }
}
