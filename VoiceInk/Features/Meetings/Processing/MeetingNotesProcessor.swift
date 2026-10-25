import Accelerate
import Foundation
import LLMkit
import SwiftData
import os

enum MeetingNotesError: LocalizedError {
    case noAudioRecorded

    var errorDescription: String? {
        switch self {
        case .noAudioRecorded:
            return String(localized: "No audio was recorded. Check that VoiceInk can record the screen and system audio.")
        }
    }
}

/// Turns a finished meeting recording into a speaker-labeled transcript and AI meeting notes,
/// then saves both to History.
@MainActor
struct MeetingNotesProcessor {
    struct Input {
        let recording: MeetingAudioCapture.Recording
        let duration: TimeInterval
        let appName: String?
    }

    private enum Speaker {
        case me
        case others

        var label: String {
            switch self {
            case .me: return String(localized: "Me")
            case .others: return String(localized: "Others")
            }
        }
    }

    private struct Line {
        let start: TimeInterval
        let speaker: Speaker
        let text: String
    }

    private static let sampleRate = AudioProcessor.AudioFormat.targetSampleRate
    private static let chunkSeconds: Double = 30
    /// Chunks quieter than this are treated as silence and skipped, which also avoids Whisper hallucinations.
    private static let silenceRMS: Float = 0.003
    private static let summaryTimeout: TimeInterval = 600
    private static let summaryChunkWords = 2500

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingNotesProcessor")
    private let engine: VoiceInkEngine
    private let aiService: AIService?

    init(engine: VoiceInkEngine, aiService: AIService?) {
        self.engine = engine
        self.aiService = aiService
    }

    func process(_ input: Input, onPhase: (String) -> Void) async throws -> Transcription {
        let modelContext = engine.modelContext
        guard
            let configuration = ModeRuntimeResolver.transcriptionConfiguration(
                mode: ModeManager.shared.currentEffectiveConfiguration,
                transcriptionModelManager: engine.transcriptionModelManager
            )
        else {
            throw TranscriptionError.noModelSelected
        }

        onPhase(String(localized: "Preparing meeting audio…"))
        let audioProcessor = AudioProcessor()
        let otherSamples = try await loadSamples(input.recording.systemAudioURL, with: audioProcessor)
        let mySamples = try await loadSamples(input.recording.microphoneURL, with: audioProcessor)

        guard !mySamples.isEmpty || !otherSamples.isEmpty else {
            throw MeetingNotesError.noAudioRecorded
        }
        let mixedURL = input.recording.directory.appendingPathComponent("meeting.wav")
        try audioProcessor.saveSamplesAsWav(samples: Self.mix(mySamples, otherSamples), to: mixedURL)

        let serviceRegistry = TranscriptionServiceRegistry(
            modelProvider: engine.whisperModelManager,
            modelsDirectory: engine.whisperModelManager.modelsDirectory,
            modelContext: modelContext
        )
        let chunksDirectory = input.recording.directory.appendingPathComponent("chunks")
        try FileManager.default.createDirectory(at: chunksDirectory, withIntermediateDirectories: true)

        let transcriptionStart = Date()
        let chunkLength = Int(Self.sampleRate * Self.chunkSeconds)
        let totalLength = max(mySamples.count, otherSamples.count)
        let chunkCount = max(1, Int((Double(totalLength) / Double(chunkLength)).rounded(.up)))
        var lines: [Line] = []

        for chunkIndex in 0..<chunkCount {
            try Task.checkCancellation()
            onPhase(
                String(
                    format: String(localized: "Transcribing meeting… %lld%%"),
                    Int64(chunkIndex * 100 / chunkCount)
                )
            )

            let range = (chunkIndex * chunkLength)..<((chunkIndex + 1) * chunkLength)
            let start = Double(range.lowerBound) / Self.sampleRate

            let othersText = try await transcribeChunk(
                otherSamples, range: range, name: "others-\(chunkIndex)", in: chunksDirectory,
                registry: serviceRegistry, configuration: configuration, audioProcessor: audioProcessor
            )
            var myText = try await transcribeChunk(
                mySamples, range: range, name: "me-\(chunkIndex)", in: chunksDirectory,
                registry: serviceRegistry, configuration: configuration, audioProcessor: audioProcessor
            )

            // Without headphones the mic also hears the call, so drop "Me" lines that just echo the others.
            if let mine = myText, let theirs = othersText, Self.isEcho(mine, of: theirs) {
                myText = nil
            }

            if let othersText {
                lines.append(Line(start: start, speaker: .others, text: othersText))
            }
            if let myText {
                lines.append(Line(start: start, speaker: .me, text: myText))
            }
        }

        await serviceRegistry.cleanup()
        try? FileManager.default.removeItem(at: chunksDirectory)
        let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

        let transcript = lines.map { line in
            let text = WordReplacementService.shared.applyReplacements(to: line.text, using: modelContext)
            return "[\(Self.timestamp(line.start))] \(line.speaker.label): \(text)"
        }
        .joined(separator: "\n")

        var notes: String?
        var notesModelName: String?
        var notesDuration: TimeInterval?
        if !transcript.isEmpty, let aiService, Self.canSummarize(with: aiService) {
            onPhase(String(localized: "Writing meeting notes…"))
            let notesStart = Date()
            do {
                notes = try await summarize(transcript, appName: input.appName, aiService: aiService)
                notesModelName = aiService.currentModel
                notesDuration = Date().timeIntervalSince(notesStart)
            } catch {
                logger.error("Meeting summary failed: \(error, privacy: .public)")
                notes = String(
                    format: String(localized: "Meeting notes could not be written: %@"),
                    EnhancementFailureFormatter.message(for: error)
                )
            }
        }

        let transcription = Transcription(
            text: transcript.isEmpty ? String(localized: "No speech was detected in this meeting.") : transcript,
            duration: input.duration,
            enhancedText: notes,
            audioFileURL: mixedURL.absoluteString,
            transcriptionModelName: configuration.model.displayName,
            aiEnhancementModelName: notesModelName,
            promptName: notes == nil ? nil : String(localized: "Meeting Notes"),
            transcriptionDuration: transcriptionDuration,
            enhancementDuration: notesDuration,
            modeName: input.appName.map { String(format: String(localized: "Meeting · %@"), $0) }
                ?? String(localized: "Meeting"),
            modeEmoji: "🗓️",
            transcriptionStatus: .completed
        )
        modelContext.insert(transcription)
        try modelContext.save()
        NotificationCenter.default.post(name: .transcriptionCreated, object: transcription)
        return transcription
    }

    // MARK: - Transcription

    private func loadSamples(_ url: URL, with audioProcessor: AudioProcessor) async throws -> [Float] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try await audioProcessor.processAudioToSamples(url)
    }

    private func transcribeChunk(
        _ samples: [Float],
        range: Range<Int>,
        name: String,
        in directory: URL,
        registry: TranscriptionServiceRegistry,
        configuration: TranscriptionRuntimeConfiguration,
        audioProcessor: AudioProcessor
    ) async throws -> String? {
        let clamped = range.clamped(to: 0..<samples.count)
        guard clamped.count > Int(Self.sampleRate) else { return nil }

        let chunk = Array(samples[clamped])
        guard Self.rms(chunk) >= Self.silenceRMS else { return nil }

        let url = directory.appendingPathComponent("\(name).wav")
        try audioProcessor.saveSamplesAsWav(samples: chunk, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let raw = try await registry.transcribe(
            audioURL: url,
            model: configuration.model,
            context: configuration.requestContext
        )
        let text = TranscriptionOutputFilter.filter(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func rms(_ samples: [Float]) -> Float {
        var value: Float = 0
        vDSP_rmsqv(samples, 1, &value, vDSP_Length(samples.count))
        return value
    }

    private static func mix(_ first: [Float], _ second: [Float]) -> [Float] {
        let count = max(first.count, second.count)
        var mixed = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let a = index < first.count ? first[index] : 0
            let b = index < second.count ? second[index] : 0
            mixed[index] = max(-1, min(1, a + b))
        }
        return mixed
    }

    private static func isEcho(_ mine: String, of theirs: String) -> Bool {
        let myWords = words(in: mine)
        let theirWords = words(in: theirs)
        guard !myWords.isEmpty, !theirWords.isEmpty else { return false }
        let shared = myWords.intersection(theirWords).count
        return Double(shared) / Double(min(myWords.count, theirWords.count)) > 0.6
    }

    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Notes

    private static func canSummarize(with aiService: AIService) -> Bool {
        aiService.selectedProvider != .voiceInkRefine && aiService.isAPIKeyValid
    }

    private func summarize(_ transcript: String, appName: String?, aiService: AIService) async throws -> String {
        let provider = aiService.selectedProvider
        let model = aiService.currentModel
        let vocabulary = CustomVocabularyService.shared.getCustomVocabulary(from: engine.modelContext)

        // Small local models have short context windows, so long meetings are condensed in parts first.
        let parts = Self.split(transcript, maxWords: Self.summaryChunkWords)
        var source = transcript
        if parts.count > 1 {
            var partNotes: [String] = []
            for (index, part) in parts.enumerated() {
                let text = try await aiService.completeChat(
                    provider: provider,
                    modelName: model,
                    messages: [.user(part)],
                    systemPrompt: Self.partPrompt(part: index + 1, of: parts.count),
                    timeout: Self.summaryTimeout
                )
                partNotes.append(AIEnhancementOutputFilter.filter(text))
            }
            source = partNotes.joined(separator: "\n\n")
        }

        var systemPrompt = Self.notesPrompt
        if let appName {
            systemPrompt += "\n\nThe call took place in \(appName)."
        }
        if !vocabulary.isEmpty {
            systemPrompt += "\n\nSpell these names and terms exactly as written: \(vocabulary)"
        }

        let notes = try await aiService.completeChat(
            provider: provider,
            modelName: model,
            messages: [.user(source)],
            systemPrompt: systemPrompt,
            timeout: Self.summaryTimeout
        )
        return AIEnhancementOutputFilter.filter(notes).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func split(_ transcript: String, maxWords: Int) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        var wordCount = 0

        for line in transcript.components(separatedBy: "\n") {
            let lineWords = line.split(separator: " ").count
            if wordCount + lineWords > maxWords, !current.isEmpty {
                parts.append(current.joined(separator: "\n"))
                current = []
                wordCount = 0
            }
            current.append(line)
            wordCount += lineWords
        }
        if !current.isEmpty {
            parts.append(current.joined(separator: "\n"))
        }
        return parts
    }

    private static func partPrompt(part: Int, of total: Int) -> String {
        """
        You are condensing part \(part) of \(total) of a meeting transcript. Lines are labeled "Me" (the user) \
        and "Others" (everyone else on the call), with [mm:ss] timestamps.
        Write dense bullet notes of everything discussed in this part: facts, numbers, names, decisions, \
        commitments and who made them, open questions. Keep the timestamps of important moments.
        Write in the same language as the transcript. Output only the notes.
        """
    }

    private static let notesPrompt = """
        You write meeting notes from a call transcript (or from condensed notes of one). Lines are labeled "Me" \
        (the user) and "Others" (everyone else on the call). Transcription can contain errors; fix obvious ones \
        from context.

        Write in the same language as the transcript, in Markdown, with exactly these sections:
        ## Summary
        Two to four sentences on what the meeting was about and where it ended up.
        ## Topics
        Bullets grouped under short bold topic names, with the key points of each.
        ## Decisions
        Bullets of what was agreed. Write "None" if nothing was decided.
        ## Action items
        Checklist lines like "- [ ] Owner: task (deadline)". Use "Me" for the user's own tasks. Write "None" if there are none.
        ## Follow-up message
        A short, friendly message the user could send to the others recapping decisions and next steps.

        Only use information from the transcript. Do not invent names, numbers or deadlines.
        """
}
