import AppKit
import Foundation
import os

/// Updates a local build the same way it was installed: by running Install.command from the cloned repo,
/// which pulls the latest code, builds it and reinstalls the app.
enum LocalUpdater {
    /// Install.command saves the repo folder here on every install.
    static let repoPathKey = "MyWhisperRepoPath"

    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "LocalUpdater")

    @MainActor
    static func runInstaller() {
        guard let installer = installerURL() else {
            logger.error("Install.command not found")
            NotificationManager.shared.showNotification(
                title: String(
                    localized: "Couldn't find Install.command. Open your VoiceInk folder and double-click Install.command."
                ),
                type: .warning,
                duration: 10
            )
            return
        }

        logger.notice("Opening \(installer.path, privacy: .public) to update")
        // .command files open in Terminal, which runs the installer and quits this app before replacing it.
        NSWorkspace.shared.open(installer)
    }

    static func installerURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let saved = UserDefaults.standard.string(forKey: repoPathKey), !saved.isEmpty {
            candidates.append(URL(fileURLWithPath: saved))
        }
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("VoiceInk"))

        return candidates
            .map { $0.appendingPathComponent("Install.command") }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
