import SwiftUI

/// The main screen — mockups 1a/1b/1c unified: layout adapts to the active
/// narration mode (CONTINUOUS / NEW ONLY / ON DEMAND). Double-tap anywhere
/// repeats the last utterance (R2.4). Tapping a box enters Focus mode (R4.1).
struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var settings = SettingsStore.shared

    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showNavigate = false

    var body: some View {
        ZStack {
            cameraLayer

            if model.focus == nil {
                HUDOverlay(detections: model.detections) { model.lock(on: $0) }
                    .ignoresSafeArea()
                chrome
            } else {
                FocusView()
            }
        }
        .background(Theme.bgDeep.ignoresSafeArea())
        .onTapGesture(count: 2) { model.repeatLast() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNavigate) { NavigateView() }
        .onAppear { model.startSession() }
    }

    // MARK: Camera / fallback

    @ViewBuilder
    private var cameraLayer: some View {
        if model.cameraAuthorized {
            CameraPreview(session: model.camera.session)
                .ignoresSafeArea()
        } else {
            // Denied or undetermined (R8.3) — also what the simulator shows.
            VStack(spacing: 18) {
                TelemetryText(text: "LIVE CAMERA FEED", size: 10, color: .white.opacity(0.3))
                if model.cameraDenied {
                    Text("Camera access is off.\nAudioVision can't see without it.")
                        .font(.system(size: 16))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.bgDeep)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(stripedBackground.ignoresSafeArea())
        }
    }

    private var stripedBackground: some View {
        // The mockups' placeholder stripes.
        LinearGradient(colors: [Theme.card, Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topTelemetry
            NavigationBanner(suggestion: model.pathSuggestion)
                .padding(.top, 10)
            GuidanceBar(nav: model.router)
                .padding(.top, 8)
            Spacer()
            bottomStack
        }
        .padding(.horizontal, 12)
    }

    private var topTelemetry: some View {
        HStack {
            HStack(spacing: 6) {
                PulseDot()
                TelemetryText(text: "\(model.detector.modelName) · \(Int(model.fps)) FPS", size: 10)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .avCard(.black.opacity(0.7), stroke: .white.opacity(0.15))
            .accessibilityLabel("Detector running at \(Int(model.fps)) frames per second")

            Spacer()

            TelemetryText(text: "\(model.detections.count) OBJECTS", size: 10)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .avCard(.black.opacity(0.7), stroke: .white.opacity(0.15))
                .accessibilityLabel("\(model.detections.count) objects in view")

            // Walking navigation, available in every mode (R13.1).
            Button {
                showNavigate = true
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.router.state == .navigating ? Theme.accent : .white)
                    .frame(width: 44, height: 44)
                    .avCard(.black.opacity(0.7), stroke: .white.opacity(0.15))
            }
            .accessibilityLabel("Navigate")
            .accessibilityHint("Search a destination for walking directions")

            // Persistent settings affordance, available in every mode (R6.8).
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .avCard(.black.opacity(0.7), stroke: .white.opacity(0.15))
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Voice, narration mode, filters, and spatial audio")
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomStack: some View {
        VStack(spacing: 10) {
            switch settings.mode {
            case .continuous:
                PanIndicator(pan: model.narration.lastPan)
                NarrationBar(speech: model.speech)
                continuousControls

            case .newOnly:
                newObjectCard
                newOnlyControls

            case .onDemand:
                onDemandControls
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: 1a — continuous

    private var continuousControls: some View {
        HStack(spacing: 8) {
            Button {
                model.audioPaused.toggle()
            } label: {
                Text(model.audioPaused ? "RESUME AUDIO" : "PAUSE AUDIO")
                    .font(Theme.telemetry(12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.bgDeep)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent))
            }
            .accessibilityLabel(model.audioPaused ? "Resume audio narration" : "Pause audio narration")

            squareButton("HIST", label: "Detection history") { showHistory = true }
            squareButton("SET", label: "Settings") { showSettings = true }
        }
    }

    // MARK: 1b — new only

    @ViewBuilder
    private var newObjectCard: some View {
        HStack(spacing: 8) {
            PulseDot()
            TelemetryText(text: "LISTENING FOR NEW OBJECTS", size: 10, color: .white.opacity(0.7))
        }
        if let det = model.narration.lastAnnouncement {
            VStack(alignment: .leading, spacing: 0) {
                TelemetryText(text: "NEW OBJECT ANNOUNCED", size: 9, color: Theme.accent)
                    .padding(.bottom, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text(det.displayName)
                        .font(.system(size: 34, weight: .bold))
                        .kerning(-0.5)
                        .foregroundStyle(.white)
                    Spacer()
                    TelemetryText(text: "\(Int(det.confidence * 100))% · \(det.position.short)"
                        + (det.distanceMeters.map { String(format: " · %.1f M", $0) } ?? ""),
                        size: 12, color: .white.opacity(0.55))
                }
                Text("Ignoring \(model.narration.ignoredCount) known object\(model.narration.ignoredCount == 1 ? "" : "s") in view. Double-tap anywhere to repeat.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 12)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .avCard(Theme.bgDeep, stroke: .white.opacity(0.14))
        }
    }

    private var newOnlyControls: some View {
        HStack(spacing: 8) {
            Button {
                model.repeatLast()
            } label: {
                Text("Repeat")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.bgDeep)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(.white))
            }
            .accessibilityHint("Speaks the last announcement again")

            Button {
                model.audioPaused.toggle()
            } label: {
                Text(model.audioPaused ? "Unmute" : "Mute")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .avCard(.white.opacity(0.08), stroke: .white.opacity(0.25))
            }
        }
    }

    // MARK: 1c — on demand

    private var onDemandControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Verbosity.allCases, id: \.self) { v in
                    Button {
                        settings.verbosity = v
                    } label: {
                        TelemetryText(text: v.rawValue, size: 11,
                                      color: settings.verbosity == v ? Theme.bgDeep : .white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radius)
                                    .fill(settings.verbosity == v ? Theme.accent : .white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radius)
                                    .stroke(.white.opacity(settings.verbosity == v ? 0 : 0.2), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("\(v.rawValue) verbosity")
                    .accessibilityAddTraits(settings.verbosity == v ? .isSelected : [])
                }
            }

            Button {
                model.describeScene()
            } label: {
                Text("Describe scene")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.bgDeep)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.accent))
            }
            .accessibilityHint("Speaks everything currently in view")

            Text(model.voiceQuery.isListening
                 ? "Listening… release to ask"
                 : "Or hold here and ask: “Where is my cup?”")
                .font(.system(size: 12))
                .foregroundStyle(model.voiceQuery.isListening ? Theme.accent : .white.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.3, perform: {}, onPressingChanged: { pressing in
                    if pressing {
                        model.beginVoiceQuestion()
                    } else if model.voiceQuery.isListening {
                        model.endVoiceQuestion()
                    }
                })
                .accessibilityLabel("Ask a question")
                .accessibilityHint("Hold, ask where an object is, then release")

            HStack(spacing: 8) {
                squareButton("HIST", label: "Detection history") { showHistory = true }
                squareButton("SET", label: "Settings") { showSettings = true }
                Spacer()
            }
        }
    }

    private func squareButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TelemetryText(text: title, size: 9)
                .frame(width: 52, height: 52)
                .avCard(.white.opacity(0.1), stroke: .white.opacity(0.25))
        }
        .accessibilityLabel(label)
    }
}
