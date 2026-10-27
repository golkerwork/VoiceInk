import AppKit
import Foundation
import os

/// Runs the meeting notetaker: notices when a call starts, records it without a bot,
/// stops when the call ends, and turns the recording into notes in History.
@MainActor
final class MeetingNotesCoordinator: ObservableObject {
    static let shared = MeetingNotesCoordinator()

    enum State: Equatable {
        case idle
        case starting
        case recording(since: Date, appName: String?)
        case processing(String)
    }

    static let detectionEnabledKey = "MeetingDetectionEnabled"

    @Published private(set) var state: State = .idle
    @Published var isDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(isDetectionEnabled, forKey: Self.detectionEnabledKey) }
    }

    private static let pollInterval: TimeInterval = 3
    /// How long the meeting app must be off the mic before an auto-started recording stops.
    private static let autoStopDelay: TimeInterval = 20

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingNotesCoordinator")
    private let capture = MeetingAudioCapture()
    private weak var engine: VoiceInkEngine?
    private weak var aiService: AIService?
    private var pollTimer: Timer?
    private var currentRecording: MeetingAudioCapture.Recording?
    /// Apps we already offered to record while they hold the mic, so the prompt shows once per call.
    private var promptedApps: Set<String> = []
    private var recordingHasSeenMeetingApp = false
    private var lastMeetingAppActivity: Date?

    private init() {
        UserDefaults.standard.register(defaults: [Self.detectionEnabledKey: true])
        isDetectionEnabled = UserDefaults.standard.bool(forKey: Self.detectionEnabledKey)

        capture.onUnexpectedStop = { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }

    func configure(engine: VoiceInkEngine, aiService: AIService) {
        self.engine = engine
        self.aiService = aiService

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    // MARK: - Recording

    func startRecording(appName: String? = nil) {
        guard state == .idle else { return }
        state = .starting

        Task {
            do {
                let recording = try await capture.start(in: Self.newMeetingDirectory())
                currentRecording = recording
                recordingHasSeenMeetingApp = false
                lastMeetingAppActivity = nil
                state = .recording(since: Date(), appName: appName ?? MeetingAppMonitor.activeMeetingApps().first?.name)
                NotificationManager.shared.showNotification(
                    title: String(localized: "Taking meeting notes. They'll be in History when the call ends."),
                    type: .success,
                    duration: 4
                )
            } catch {
                logger.error("Could not start meeting notes: \(error, privacy: .public)")
                state = .idle
                showPermissionHelp()
            }
        }
    }

    func stopRecording() {
        guard case .recording(let since, let appName) = state, let recording = currentRecording else { return }
        currentRecording = nil
        state = .processing(String(localized: "Finishing recording…"))

        Task {
            await capture.stop()
            await process(recording, duration: Date().timeIntervalSince(since), appName: appName)
        }
    }

    private func process(_ recording: MeetingAudioCapture.Recording, duration: TimeInterval, appName: String?) async {
        guard let engine else {
            state = .idle
            return
        }

        let processor = MeetingNotesProcessor(engine: engine, aiService: aiService)
        do {
            let transcription = try await processor.process(
                MeetingNotesProcessor.Input(recording: recording, duration: duration, appName: appName),
                onPhase: { [weak self] phase in self?.state = .processing(phase) }
            )
            state = .idle
            NotificationManager.shared.showNotification(
                title: String(localized: "Meeting notes are ready in History"),
                type: .success,
                duration: 8,
                actionButton: (
                    label: String(localized: "Copy Notes"),
                    action: { Self.copyToClipboard(transcription) }
                )
            )
        } catch {
            logger.error("Meeting processing failed: \(error, privacy: .public)")
            state = .idle
            NotificationManager.shared.showNotification(
                title: String(
                    format: String(localized: "Meeting notes failed: %@"),
                    error.localizedDescription
                ),
                type: .error,
                duration: 8
            )
        }
    }

    // MARK: - Detection

    private func poll() {
        // While idle with nothing to watch for, skip the Core Audio query entirely.
        if state == .idle, !isDetectionEnabled || DictationPauseController.shared.isPaused {
            return
        }
        let activeApps = MeetingAppMonitor.activeMeetingApps()
        let activeIDs = Set(activeApps.map(\.bundleID))
        promptedApps.formIntersection(activeIDs)

        switch state {
        case .recording:
            if !activeApps.isEmpty {
                recordingHasSeenMeetingApp = true
                lastMeetingAppActivity = Date()
            } else if recordingHasSeenMeetingApp,
                let lastMeetingAppActivity,
                Date().timeIntervalSince(lastMeetingAppActivity) > Self.autoStopDelay
            {
                logger.notice("Meeting app released the microphone; stopping meeting notes")
                stopRecording()
            }

        case .idle:
            guard isDetectionEnabled, let app = activeApps.first(where: { !promptedApps.contains($0.bundleID) }) else {
                return
            }
            promptedApps.insert(app.bundleID)
            NotificationManager.shared.showNotification(
                title: String(format: String(localized: "Call detected in %@"), app.name),
                type: .info,
                duration: 15,
                actionButton: (
                    label: String(localized: "Take Notes"),
                    action: { [weak self] in self?.startRecording(appName: app.name) }
                )
            )

        case .starting, .processing:
            return
        }
    }

    // MARK: - Helpers

    private func showPermissionHelp() {
        NotificationManager.shared.showNotification(
            title: String(localized: "Allow Screen & System Audio Recording for VoiceInk to take meeting notes"),
            type: .warning,
            duration: 10,
            actionButton: (
                label: String(localized: "Open Settings"),
                action: {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        )
    }

    private static func copyToClipboard(_ transcription: Transcription) {
        let content = [transcription.enhancedText, transcription.text]
            .compactMap { $0 }
            .joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private static func newMeetingDirectory() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
            .appendingPathComponent("Meetings")
            .appendingPathComponent(formatter.string(from: Date()))
    }
}
