import SwiftUI

/// Session detection timeline with per-row replay (mockup 1f, R5).
struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.history.entries.isEmpty {
                Spacer()
                Text("No detections yet.\nPoint the camera at the world and they'll appear here.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.history.entries.enumerated()), id: \.element.id) { index, entry in
                            timelineRow(entry, isLatest: index == 0)
                        }
                    }
                }
            }

            Button {
                replayAll()
            } label: {
                Text("Replay full session audio")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .avCard(.white.opacity(0.06), stroke: .white.opacity(0.2))
            }
            .disabled(model.history.entries.isEmpty)
            .padding(.top, 12)
            .accessibilityHint("Speaks every logged detection in order")
        }
        .padding(EdgeInsets(top: 24, leading: 16, bottom: 20, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            TelemetryText(text: model.history.sessionHeader, size: 9, color: .white.opacity(0.45))
            Spacer()
            TelemetryText(text: "\(model.history.entries.count) DETECTIONS", size: 9, color: Theme.accent)
        }
        .padding(.bottom, 14)
        .accessibilityElement()
        .accessibilityLabel("Session history, \(model.history.entries.count) detections")
    }

    private func timelineRow(_ entry: HistoryEntry, isLatest: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isLatest ? Theme.accent : .white.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .padding(.top, 18)
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label.capitalized)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    TelemetryText(text: entry.telemetryLine, size: 10, color: .white.opacity(0.4))
                }
                Spacer()
                TelemetryText(text: entry.timeString, size: 10, color: .white.opacity(0.45))
                Button {
                    model.speech.speak(entry.spokenSentence, interrupt: true)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .avCard(.clear, stroke: .white.opacity(0.2))
                }
                .accessibilityLabel("Replay \(entry.label)")
            }
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func replayAll() {
        for entry in model.history.entries.reversed() {
            model.speech.speak(entry.spokenSentence)
        }
    }
}
