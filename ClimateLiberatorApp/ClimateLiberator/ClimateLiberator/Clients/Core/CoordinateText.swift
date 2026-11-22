import Foundation

/// Reads coordinates the way people paste them: "11.1085, 77.3411",
/// "11.1085 77.3411" or "11.1085°N, 77.3411°E" (S and W make the value negative).
nonisolated enum CoordinateText {
    static func parse(_ text: String) -> (latitude: Double, longitude: Double)? {
        let separators = CharacterSet(charactersIn: ", ;\t")
        let parts = text.uppercased().components(separatedBy: separators).filter { !$0.isEmpty }
        guard parts.count == 2,
              let latitude = degrees(parts[0], negative: "S"),
              let longitude = degrees(parts[1], negative: "W"),
              isValid(latitude: latitude, longitude: longitude) else { return nil }
        return (latitude, longitude)
    }

    static func isValid(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    static func format(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    private static func degrees(_ part: String, negative: Character) -> Double? {
        var text = part.replacingOccurrences(of: "°", with: "")
        var sign = 1.0
        if let last = text.last, last.isLetter {
            if last == negative { sign = -1 }
            else if !"NE".contains(last) { return nil }
            text.removeLast()
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return sign * value
    }
}
