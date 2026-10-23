import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var whisperKitEngine: WhisperKitEngine
    var parakeetEngine: ParakeetEngine
    var updateChecker: UpdateChecker?

    /// Notification visibility from `PermissionsController`, forwarded to the
    /// General tab so it can warn when browser-meeting consent cannot reach the
    /// user. Nil until the first permission check completes.
    var notificationVisibility: NotificationVisibility?
    /// Required: the same actor instance the pipeline writes to, so the Stats
    /// tab and the pipeline don't race two writers on `recognition_log.jsonl`.
    var recognitionStatsLog: RecognitionStatsLog
    /// Same actor instance the pipeline writes to, so the Processing Stats tab
    /// and the pipeline don't race two writers on `stage_timing.jsonl`.
    var stageTimingLog: StageTimingLog
    /// Factory for the voice-enrollment diarizer. nil → enroll button hidden.
    var enrollmentDiarizerFactory: (() -> any DiarizationProvider)?
    /// True when a meeting is currently waiting on a naming dialog. We gate
    /// the enroll button to avoid two `SpeakerNamingView` instances.
    var namingDialogActive: Bool = false
    /// True when the pipeline is processing a job — soft hint only.
    var pipelineBusy: Bool = false
    var onSpeakerMutate: (() -> Void)?

    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider()
            detailView(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: 760,
            idealWidth: 900,
            maxWidth: 1120,
            minHeight: 520,
            idealHeight: 640,
            maxHeight: .infinity,
        )
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image("SawtiLogo", bundle: .main)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sawti")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, alignment: .leading)

            Divider()
                .frame(height: 42)

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button {
                            selection = tab
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 17, weight: .regular))
                                Text(tab.label)
                                    .font(.system(size: 11, weight: selection == tab ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                            .frame(minWidth: 78, maxWidth: 106, minHeight: 54)
                            .background {
                                if selection == tab {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.13))
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(A11yID.settingsTab(tab.rawValue))
                        .accessibilityLabel(tab.label)
                        .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(
                settings: settings,
                notificationVisibility: notificationVisibility,
            )

        case .audio:
            AudioSettingsView(settings: settings)

        case .transcription:
            TranscriptionSettingsView(
                settings: settings,
                whisperKitEngine: whisperKitEngine,
                parakeetEngine: parakeetEngine,
            )

        case .speakers:
            SpeakersSettingsView(
                settings: settings,
                recognitionStatsLog: recognitionStatsLog,
                stageTimingLog: stageTimingLog,
                enrollmentDiarizerFactory: enrollmentDiarizerFactory,
                namingDialogActive: namingDialogActive,
                pipelineBusy: pipelineBusy,
                onSpeakerMutate: onSpeakerMutate,
            )

        case .output:
            OutputSettingsView(settings: settings)

        case .advanced:
            AdvancedSettingsView(settings: settings)

        case .about:
            AboutSettingsView(settings: settings, updateChecker: updateChecker)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, audio, transcription, speakers, output, advanced, about

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .general: "General"
        case .audio: "Audio"
        case .transcription: "Transcription"
        case .speakers: "Speakers"
        case .output: "Output"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .audio: "mic"
        case .transcription: "waveform"
        case .speakers: "person.2"
        case .output: "doc.text"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}
