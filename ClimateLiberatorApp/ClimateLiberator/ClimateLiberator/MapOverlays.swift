import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

final class RateOfSpreadOverlay: NSObject, MKOverlay {
    let image: CGImage
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    let values: [Double?]
    let width: Int
    let height: Int
    let minValue: Double
    let maxValue: Double
    let minLon: Double
    let maxLon: Double
    let minLat: Double
    let maxLat: Double
    let cellSize: Double

    init(image: CGImage,
         boundingMapRect: MKMapRect,
         coordinate: CLLocationCoordinate2D,
         values: [Double?],
         width: Int,
         height: Int,
         minValue: Double,
         maxValue: Double,
         minLon: Double,
         maxLon: Double,
         minLat: Double,
         maxLat: Double,
         cellSize: Double) {
        self.image = image
        self.boundingMapRect = boundingMapRect
        self.coordinate = coordinate
        self.values = values
        self.width = width
        self.height = height
        self.minValue = minValue
        self.maxValue = maxValue
        self.minLon = minLon
        self.maxLon = maxLon
        self.minLat = minLat
        self.maxLat = maxLat
        self.cellSize = cellSize
        super.init()
    }

    func value(at coordinate: CLLocationCoordinate2D) -> Double? {
        return sample(at: coordinate)?.value
    }

    func sample(at coordinate: CLLocationCoordinate2D) -> (value: Double, center: CLLocationCoordinate2D)? {
        let col = Int((coordinate.longitude - minLon) / cellSize)
        let row = Int((maxLat - coordinate.latitude) / cellSize)
        guard col >= 0, col < width, row >= 0, row < height else { return nil }
        guard let value = values[row * width + col] else { return nil }
        let centerLat = maxLat - cellSize * (Double(row) + 0.5)
        let centerLon = minLon + cellSize * (Double(col) + 0.5)
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        return (value, center)
    }

    func coordinate(forCellID cellID: Int) -> CLLocationCoordinate2D? {
        guard cellID >= 1, cellID <= width * height else { return nil }
        let zeroIndexed = cellID - 1
        let row = zeroIndexed / width
        let col = zeroIndexed % width
        let latitude = maxLat - cellSize * (Double(row) + 0.5)
        let longitude = minLon + cellSize * (Double(col) + 0.5)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class RateOfSpreadOverlayRenderer: MKOverlayRenderer {
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? RateOfSpreadOverlay else { return }
        let rect = self.rect(for: overlay.boundingMapRect)
        context.saveGState()
        context.setAlpha(0.75)
        context.draw(overlay.image, in: rect)
        context.restoreGState()
    }
}

struct IdentifyHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Identify ROS")
                .font(.caption).bold()
            Text("Click the map to probe the rate of spread at that point.")
                .font(.caption)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .foregroundColor(.white)
    }
}

final class IgnitionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

struct CompassButton: View {
    let angle: CLLocationDirection
    let theme: ThemeStyle
    let action: () -> Void

    private var rotation: Angle { Angle(degrees: -angle) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white, Color.red)
                    .rotationEffect(rotation)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset bearing")
    }
}

struct HistoryRow: View {
    let summary: RunSummary
    let theme: ThemeStyle

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.timestamp, style: .date)
                Text(summary.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(theme.subtleTextColor)
            }
            Spacer()
            if let burnt = aggregatedBurnt(for: summary),
               let total = aggregatedTotal(for: summary) {
                Text("\(formattedCount(burnt)) / \(formattedCount(total)) burnt")
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            } else {
                Text("—")
                    .foregroundColor(theme.subtleTextColor)
            }
        }
        .padding()
        .glassBackground(material: theme.material,
                         tint: theme.cardBackground.opacity(0.9),
                         cornerRadius: 16,
                         strokeColor: theme.borderColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

func formattedCount(_ value: Int?) -> String {
    guard let value else { return "—" }
    return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
}

func formattedROS(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.3f", value)
}

func aggregatedBurnt(for summary: RunSummary) -> Int? {
    let values = summary.simulations.compactMap { $0.burnt }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
}

private func aggregatedTotal(for summary: RunSummary) -> Int? {
    let values = summary.simulations.compactMap { $0.resolvedTotal }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
}

extension SimulationStats {
    var resolvedTotal: Int? {
        if let totalCells { return totalCells }
        let components = [available, burnt, nonBurnable, firebreak]
        if components.contains(where: { $0 == nil }) { return nil }
        return components.compactMap { $0 }.reduce(0, +)
    }
}

