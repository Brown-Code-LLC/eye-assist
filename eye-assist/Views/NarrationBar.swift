import SwiftUI

/// Bottom narration bar: waveform + current/last sentence (mockup 1a, R2.3).
struct NarrationBar: View {
    @ObservedObject var speech: SpeechService

    var body: some View {
        HStack(spacing: 12) {
            Waveform(active: speech.isSpeaking)
            Text(speech.currentText.isEmpty ? "Listening for objects…" : "“\(speech.currentText)”")
                .font(.system(size: 14))
                .lineSpacing(2)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(speech.currentText.isEmpty ? 0.5 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .fill(.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(width: 3)
        }
        .accessibilityElement()
        .accessibilityLabel("Narration")
        .accessibilityValue(speech.currentText.isEmpty ? "Idle" : speech.currentText)
    }
}
