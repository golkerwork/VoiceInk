import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import os

enum MeetingCaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return String(localized: "No display is available for system audio capture")
        }
    }
}

/// Records system audio (everyone else on the call) and the microphone (you) into two separate files
/// with ScreenCaptureKit, so no bot has to join the meeting.
final class MeetingAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Recording {
        let directory: URL
        let systemAudioURL: URL
        let microphoneURL: URL
    }

    var onUnexpectedStop: ((Error) -> Void)?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingAudioCapture")
    private let sampleQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.meeting-audio")
    private var stream: SCStream?

    // Only touched on sampleQueue.
    private var recording: Recording?
    private var systemAudioFile: AVAudioFile?
    private var microphoneFile: AVAudioFile?

    func start(in directory: URL) async throws -> Recording {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw MeetingCaptureError.noDisplay
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recording = Recording(
            directory: directory,
            systemAudioURL: directory.appendingPathComponent("system.caf"),
            microphoneURL: directory.appendingPathComponent("microphone.caf")
        )

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.captureMicrophone = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        // A video stream is required, but nothing reads it, so keep it tiny and slow.
        configuration.width = 64
        configuration.height = 64
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)

        sampleQueue.sync {
            self.recording = recording
            self.systemAudioFile = nil
            self.microphoneFile = nil
        }

        try await stream.startCapture()
        self.stream = stream
        logger.notice("Meeting capture started in \(directory.lastPathComponent, privacy: .public)")
        return recording
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil

        do {
            try await stream.stopCapture()
        } catch {
            logger.error("Failed to stop meeting capture: \(error, privacy: .public)")
        }

        finishFiles()
        logger.notice("Meeting capture stopped")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let recording else { return }

        switch type {
        case .audio:
            append(sampleBuffer, to: &systemAudioFile, url: recording.systemAudioURL)
        case .microphone:
            append(sampleBuffer, to: &microphoneFile, url: recording.microphoneURL)
        default:
            return
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        logger.error("Meeting capture stopped unexpectedly: \(error, privacy: .public)")
        self.stream = nil
        sampleQueue.async { [weak self] in
            self?.closeFiles()
            self?.onUnexpectedStop?(error)
        }
    }

    // MARK: - Private

    private func finishFiles() {
        sampleQueue.sync {
            closeFiles()
        }
    }

    /// Must run on sampleQueue. AVAudioFile finalizes the file when it is released.
    private func closeFiles() {
        systemAudioFile = nil
        microphoneFile = nil
        recording = nil
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to file: inout AVAudioFile?, url: URL) {
        guard let formatDescription = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        do {
            if file == nil {
                let fileSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
                file = try AVAudioFile(
                    forWriting: url,
                    settings: fileSettings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
            }
            guard let outputFile = file else { return }

            // Skip buffers whose format changed mid-call (for example, a new mic was plugged in).
            let processingFormat = outputFile.processingFormat
            guard processingFormat.sampleRate == format.sampleRate,
                processingFormat.channelCount == format.channelCount,
                processingFormat.commonFormat == format.commonFormat,
                processingFormat.isInterleaved == format.isInterleaved
            else { return }

            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard
                    let buffer = AVAudioPCMBuffer(
                        pcmFormat: processingFormat,
                        bufferListNoCopy: audioBufferList.unsafePointer
                    )
                else { return }
                try outputFile.write(from: buffer)
            }
        } catch {
            logger.error("Failed to write meeting audio to \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }
}
