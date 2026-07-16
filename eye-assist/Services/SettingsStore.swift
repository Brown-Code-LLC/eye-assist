import Foundation
import AVFoundation
import Combine

enum NarrationMode: String, CaseIterable, Codable {
    case newOnly = "NEW ONLY"
    case continuous = "CONTINUOUS"
    case onDemand = "ON DEMAND"
}

enum Verbosity: String, CaseIterable, Codable {
    case brief = "BRIEF"
    case detailed = "DETAILED"
    case full = "FULL"
}

/// Persisted user settings (R6.*). @Published + UserDefaults so changes both
/// re-render SwiftUI and reach services synchronously.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let d = UserDefaults.standard

    @Published var onboardingComplete: Bool {
        didSet { d.set(onboardingComplete, forKey: "onboardingComplete") }
    }
    @Published var mode: NarrationMode {
        didSet { d.set(mode.rawValue, forKey: "mode") }
    }
    @Published var verbosity: Verbosity {
        didSet { d.set(verbosity.rawValue, forKey: "verbosity") }
    }
    @Published var voiceIdentifier: String? {
        didSet { d.set(voiceIdentifier, forKey: "voiceIdentifier") }
    }
    /// 0…1 slider position, mapped to AVSpeechUtterance rate around the default.
    @Published var speechSpeed: Double {
        didSet { d.set(speechSpeed, forKey: "speechSpeed") }
    }
    @Published var spatialAudio: Bool {
        didSet { d.set(spatialAudio, forKey: "spatialAudio") }
    }
    @Published var readTextAloud: Bool {
        didSet { d.set(readTextAloud, forKey: "readTextAloud") }
    }
    // v2 key: v1 predates the street category and would leave it disabled forever.
    @Published var enabledCategories: Set<FilterCategory> {
        didSet { d.set(enabledCategories.map(\.rawValue), forKey: "enabledCategories.v2") }
    }

    private init() {
        onboardingComplete = d.bool(forKey: "onboardingComplete")
        mode = NarrationMode(rawValue: d.string(forKey: "mode") ?? "") ?? .continuous
        verbosity = Verbosity(rawValue: d.string(forKey: "verbosity") ?? "") ?? .detailed
        voiceIdentifier = d.string(forKey: "voiceIdentifier")
        speechSpeed = d.object(forKey: "speechSpeed") as? Double ?? 0.6
        spatialAudio = d.object(forKey: "spatialAudio") as? Bool ?? true
        readTextAloud = d.object(forKey: "readTextAloud") as? Bool ?? true
        if let raw = d.stringArray(forKey: "enabledCategories.v2") {
            enabledCategories = Set(raw.compactMap(FilterCategory.init(rawValue:)))
        } else {
            // Defaults: everything ON except Small items (mockup 1e + street use).
            enabledCategories = [.people, .vehicles, .street, .furniture, .other]
        }
    }

    /// AVSpeechUtterance rate from the 0…1 slider.
    var utteranceRate: Float {
        let minR = AVSpeechUtteranceMinimumSpeechRate
        let maxR = AVSpeechUtteranceMaximumSpeechRate
        // Keep usable band: 0.3…0.85 of the full range.
        let t = Float(0.3 + speechSpeed * 0.55)
        return minR + (maxR - minR) * t
    }

    var voice: AVSpeechSynthesisVoice? {
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    var voiceDisplayName: String {
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            return "\(v.name) · \(v.language)".uppercased()
        }
        return "SYSTEM · EN-US"
    }

    func isEnabled(_ category: FilterCategory) -> Bool {
        enabledCategories.contains(category)
    }
}
