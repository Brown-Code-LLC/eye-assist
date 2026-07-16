import SwiftUI
import AVFoundation

/// Voice, speed, narration mode, detection filters, spatial audio
/// (mockup 1e, R6).
struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var showVoicePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("VOICE") {
                    VStack(spacing: 0) {
                        Button {
                            showVoicePicker = true
                        } label: {
                            HStack {
                                Text("Voice")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                                Spacer()
                                TelemetryText(text: settings.voiceDisplayName, size: 11, color: Theme.accent)
                            }
                            .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
                        }
                        .accessibilityHint("Choose the narration voice")

                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

                        HStack(spacing: 16) {
                            Text("Speed")
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                            Slider(value: $settings.speechSpeed, in: 0...1)
                                .tint(Theme.accent)
                                .accessibilityLabel("Speech speed")
                        }
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                    .avCard()
                }

                section("NARRATION MODE") {
                    HStack(spacing: 6) {
                        ForEach([NarrationMode.newOnly, .continuous, .onDemand], id: \.self) { mode in
                            Button {
                                settings.mode = mode
                            } label: {
                                TelemetryText(text: mode.rawValue, size: 11,
                                              color: settings.mode == mode ? Theme.bgDeep : .white)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.radius)
                                            .fill(settings.mode == mode ? Theme.accent : .white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.radius)
                                            .stroke(.white.opacity(settings.mode == mode ? 0 : 0.15), lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel("\(mode.rawValue) mode")
                            .accessibilityAddTraits(settings.mode == mode ? .isSelected : [])
                        }
                    }
                }

                section("VERBOSITY") {
                    HStack(spacing: 6) {
                        ForEach(Verbosity.allCases, id: \.self) { v in
                            Button {
                                settings.verbosity = v
                            } label: {
                                TelemetryText(text: v.rawValue, size: 11,
                                              color: settings.verbosity == v ? Theme.bgDeep : .white)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.radius)
                                            .fill(settings.verbosity == v ? Theme.accent : .white.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.radius)
                                            .stroke(.white.opacity(settings.verbosity == v ? 0 : 0.15), lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel("\(v.rawValue) verbosity")
                            .accessibilityAddTraits(settings.verbosity == v ? .isSelected : [])
                        }
                    }
                }

                section("DETECTION FILTERS") {
                    VStack(spacing: 0) {
                        ForEach([FilterCategory.people, .vehicles, .street, .furniture, .smallItems], id: \.self) { cat in
                            filterRow(cat)
                            if cat != .smallItems {
                                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                            }
                        }
                    }
                    .avCard()
                }

                section("TEXT READING") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read text aloud")
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                            Text("signs, labels, doors, documents")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Toggle("", isOn: $settings.readTextAloud)
                            .labelsHidden()
                            .tint(Theme.accent)
                            .accessibilityLabel("Read text aloud")
                    }
                    .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
                    .avCard()
                }

                section("SPATIAL AUDIO") {
                    HStack {
                        Text("Pan by object position")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                        Spacer()
                        Toggle("", isOn: $settings.spatialAudio)
                            .labelsHidden()
                            .tint(Theme.accent)
                            .accessibilityLabel("Spatial audio panning")
                    }
                    .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
                    .avCard()
                }
            }
            .padding(EdgeInsets(top: 24, leading: 16, bottom: 30, trailing: 16))
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showVoicePicker) { voicePicker }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TelemetryText(text: title, size: 9, color: .white.opacity(0.45))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func filterRow(_ cat: FilterCategory) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.displayName)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Text(cat.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.enabledCategories.contains(cat) },
                set: { on in
                    if on { settings.enabledCategories.insert(cat) }
                    else { settings.enabledCategories.remove(cat) }
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
            .accessibilityLabel("\(cat.displayName) detection")
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }

    private var voicePicker: some View {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(voices, id: \.identifier) { voice in
                    Button {
                        settings.voiceIdentifier = voice.identifier
                        showVoicePicker = false
                    } label: {
                        HStack {
                            Text(voice.name)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                            Spacer()
                            TelemetryText(text: voice.language, size: 10,
                                          color: settings.voiceIdentifier == voice.identifier
                                              ? Theme.accent : .white.opacity(0.4))
                        }
                        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                    }
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                }
            }
            .padding(.top, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}
