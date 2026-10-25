import SwiftData
import SwiftUI

struct MeetingsView: View {
    @EnvironmentObject private var aiService: AIService
    @ObservedObject private var meetingNotes = MeetingNotesCoordinator.shared
    @Query(
        filter: #Predicate<Transcription> { $0.modeEmoji == "🗓️" },
        sort: \Transcription.timestamp,
        order: .reverse
    )
    private var meetings: [Transcription]
    @State private var expandedMeetingID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompactHeroSection(
                    icon: "person.2.wave.2.fill",
                    title: "Meetings",
                    description:
                        "Records your calls without a bot joining, then writes a transcript and notes with decisions and action items.",
                    maxDescriptionWidth: 480
                )

                controlCard
                meetingsList
            }
            .padding(24)
        }
    }

    // MARK: - Controls

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                statusView
                Spacer()
                actionButton
            }

            Divider()

            Toggle("Offer to take notes when a call starts", isOn: $meetingNotes.isDetectionEnabled)
                .toggleStyle(.switch)

            notesModelStatus
        }
        .padding(16)
        .background(AppCardBackground())
    }

    @ViewBuilder
    private var statusView: some View {
        switch meetingNotes.state {
        case .idle:
            Label("Not recording", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "hourglass")
        case .recording(let since, let appName):
            TimelineView(.periodic(from: since, by: 1)) { context in
                Label(
                    recordingLabel(elapsed: context.date.timeIntervalSince(since), appName: appName),
                    systemImage: "record.circle.fill"
                )
                .foregroundStyle(.red)
            }
        case .processing(let phase):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(phase)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch meetingNotes.state {
        case .idle:
            Button("Start Meeting Notes") {
                meetingNotes.startRecording()
            }
            .buttonStyle(.borderedProminent)
        case .recording:
            Button("Stop and Write Notes") {
                meetingNotes.stopRecording()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .starting, .processing:
            EmptyView()
        }
    }

    @ViewBuilder
    private var notesModelStatus: some View {
        if let notesModel = MeetingNotesProcessor.notesModel(for: aiService) {
            Text(
                String(
                    format: String(localized: "Notes are written by %@ (%@)."),
                    notesModel.provider.rawValue,
                    notesModel.model
                )
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Choose an AI model to get meeting notes. Without one you only get the transcript.")
                    .font(.system(size: 12))
                Spacer()
                Button("AI Models") {
                    MainWindowNavigation.shared.navigate(to: .models)
                }
            }
        }
    }

    private func recordingLabel(elapsed: TimeInterval, appName: String?) -> String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let time = String(format: "%d:%02d", minutes, seconds)
        if let appName {
            return String(format: String(localized: "Recording %@ · %@"), appName, time)
        }
        return String(format: String(localized: "Recording · %@"), time)
    }

    // MARK: - List

    @ViewBuilder
    private var meetingsList: some View {
        if meetings.isEmpty {
            Text("Your meetings will show up here.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Past meetings")
                    .font(.system(size: 15, weight: .semibold))

                ForEach(meetings) { meeting in
                    MeetingRow(
                        meeting: meeting,
                        isExpanded: expandedMeetingID == meeting.id,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expandedMeetingID = expandedMeetingID == meeting.id ? nil : meeting.id
                            }
                        }
                    )
                }
            }
        }
    }
}

private struct MeetingRow: View {
    let meeting: Transcription
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var showsTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.modeName ?? String(localized: "Meeting"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
            }
        }
        .padding(14)
        .background(AppCardBackground(isSelected: isExpanded))
    }

    @ViewBuilder
    private var expandedContent: some View {
        if let notes = meeting.enhancedText, !notes.isEmpty {
            HStack {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                CopyIconButton(textToCopy: notes)
            }
            MarkdownContentView(notes, fontSize: 13, foregroundColor: .primary)
        }

        HStack {
            Button(showsTranscript ? "Hide Transcript" : "Show Transcript") {
                showsTranscript.toggle()
            }
            .buttonStyle(.link)
            Spacer()
            CopyIconButton(textToCopy: meeting.text)
        }

        if showsTranscript {
            Text(meeting.text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitle: String {
        let date = meeting.timestamp.formatted(date: .abbreviated, time: .shortened)
        let minutes = max(1, Int((meeting.duration / 60).rounded()))
        return String(format: String(localized: "%@ · %lld min"), date, Int64(minutes))
    }
}
