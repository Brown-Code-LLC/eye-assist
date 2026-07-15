import SwiftUI
import AVFoundation
import Speech

/// First-launch setup (mockup 1d, R8): headline, on-device explanation,
/// permission rows with GRANTED/ALLOW chips, Continue.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var settings = SettingsStore.shared

    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized

    private var audioGranted: Bool { micGranted && speechGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TelemetryText(text: "AUDIOVISION · SETUP 1/2", size: 10, color: Theme.accent)
                .padding(.bottom, 14)

            Text("Your camera becomes your narrator.")
                .font(.system(size: 40, weight: .bold))
                .kerning(-1)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("AudioVision detects objects around you with YOLO and speaks them aloud. Everything runs on-device.")
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 16)

            Spacer()

            VStack(spacing: 10) {
                permissionRow(
                    title: "Camera",
                    subtitle: "Required for detection",
                    granted: model.cameraAuthorized
                ) {
                    Task { await model.requestCameraPermission() }
                }
                permissionRow(
                    title: "Speech & audio",
                    subtitle: "Narration and voice questions",
                    granted: audioGranted
                ) {
                    requestAudioPermissions()
                }

                Button {
                    if !model.cameraAuthorized {
                        Task {
                            await model.requestCameraPermission()
                            finishIfReady()
                        }
                    } else {
                        finishIfReady()
                    }
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.bgDeep)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(.white))
                }
                .padding(.top, 8)
                .accessibilityHint("Grants any missing permissions and opens the live camera")
            }
        }
        .padding(EdgeInsets(top: 90, leading: 22, bottom: 34, trailing: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func requestAudioPermissions() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { micGranted = granted }
        }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { speechGranted = status == .authorized }
        }
    }

    private func finishIfReady() {
        guard model.cameraAuthorized else { return }
        settings.onboardingComplete = true
        model.startSession()
    }

    @ViewBuilder
    private func permissionRow(title: String, subtitle: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                TelemetryText(text: granted ? "GRANTED" : "ALLOW",
                              size: 10,
                              color: granted ? Theme.bgDeep : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(granted ? Theme.accent : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .stroke(granted ? .clear : .white.opacity(0.35), lineWidth: 1)
                    )
            }
            .padding(16)
            .avCard()
        }
        .disabled(granted)
        .accessibilityLabel("\(title). \(subtitle). \(granted ? "Granted" : "Tap to allow")")
    }
}
