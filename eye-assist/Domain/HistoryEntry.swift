import Foundation

/// One announced detection, persisted for the History screen (R5.1).
struct HistoryEntry: Identifiable, Codable {
    var id = UUID()
    let label: String
    let confidence: Float
    let position: PositionBucket
    let distanceMeters: Double?
    let date: Date

    /// e.g. "0.94 · LEFT · 1.2 M"
    var telemetryLine: String {
        var parts = [String(format: "%.2f", confidence), position.short]
        if let d = distanceMeters { parts.append(String(format: "%.1f M", d)) }
        return parts.joined(separator: " · ")
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var spokenSentence: String {
        var s = "\(label.capitalized), \(position.spoken)"
        if let d = distanceMeters { s += ", \(spokenDistance(d))" }
        return s
    }
}
