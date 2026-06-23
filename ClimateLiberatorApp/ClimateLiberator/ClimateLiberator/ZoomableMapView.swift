import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

#if os(macOS)
struct ZoomableMapView: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var useSatellite: Bool
    @Binding var enable3D: Bool
    @Binding var heading: CLLocationDirection
    @Binding var overlay: RateOfSpreadOverlay?
    @Binding var inspectMode: Bool
    @Binding var inspectResult: InspectResult?
    @Binding var ignitionMarkers: [IgnitionMarker]
    var controller: MapController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ScrollZoomMKMapView {
        let mapView = ScrollZoomMKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.scrollDelegate = context.coordinator
        mapView.setRegion(region, animated: false)
        mapView.isRotateEnabled = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsBuildings = true
        let clickRecognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        mapView.addGestureRecognizer(clickRecognizer)
        context.coordinator.applyDisplayOptions(mapView: mapView,
                                                useSatellite: useSatellite,
                                                enable3D: enable3D)
        controller.mapView = mapView
        if let overlay {
            mapView.updateOverlay(overlay)
        }
        mapView.updateIgnitionMarkers(ignitionMarkers)
        mapView.updateIdentifyMarker(inspectResult)
        return mapView
    }

    func updateNSView(_ nsView: ScrollZoomMKMapView, context: Context) {
        context.coordinator.updateRegionIfNeeded(mapView: nsView, region: region)
        context.coordinator.applyDisplayOptions(mapView: nsView,
                                                useSatellite: useSatellite,
                                                enable3D: enable3D)
        controller.mapView = nsView
        nsView.updateOverlay(overlay)
        nsView.updateIgnitionMarkers(ignitionMarkers)
        nsView.updateIdentifyMarker(inspectResult)
        nsView.refreshScale()
    }

    final class Coordinator: NSObject, MKMapViewDelegate, ScrollZoomMapViewDelegate {
        var parent: ZoomableMapView
        private var isSyncingRegion = false

        init(_ parent: ZoomableMapView) {
            self.parent = parent
        }

        func updateRegionIfNeeded(mapView: MKMapView, region: MKCoordinateRegion) {
            guard !isSyncingRegion else { return }
            if !regionsEqual(mapView.region, region) {
                isSyncingRegion = true
                mapView.setRegion(region, animated: false)
                isSyncingRegion = false
            }
        }

        func applyDisplayOptions(mapView: MKMapView, useSatellite: Bool, enable3D: Bool) {
            let desiredType: MKMapType = useSatellite ? .hybrid : .standard
            if mapView.mapType != desiredType {
                mapView.mapType = desiredType
            }

            let camera = mapView.camera
            let targetPitch: CGFloat = enable3D ? 55 : 0
            let targetDistance: CLLocationDistance
            if enable3D {
                let minDistance: CLLocationDistance = 2200
                targetDistance = max(minDistance, camera.centerCoordinateDistance)
            } else {
                targetDistance = max(800, camera.centerCoordinateDistance)
            }

            let targetHeading: CLLocationDirection = enable3D ? camera.heading : 0
            let needsCameraUpdate =
                abs(camera.pitch - targetPitch) > 0.5 ||
                abs(camera.centerCoordinateDistance - targetDistance) > 1 ||
                abs(camera.heading - targetHeading) > 0.5 ||
                abs(camera.centerCoordinate.latitude - mapView.region.center.latitude) > 0.0001 ||
                abs(camera.centerCoordinate.longitude - mapView.region.center.longitude) > 0.0001

            if needsCameraUpdate {
                camera.pitch = targetPitch
                camera.centerCoordinate = mapView.region.center
                camera.centerCoordinateDistance = targetDistance
                camera.heading = targetHeading
                mapView.setCamera(camera, animated: false)
            }

            mapView.isPitchEnabled = true
            parent.heading = targetHeading
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isSyncingRegion else { return }
            isSyncingRegion = true
            parent.region = mapView.region
            isSyncingRegion = false
            parent.heading = mapView.camera.heading
            (mapView as? ScrollZoomMKMapView)?.refreshScale()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is RateOfSpreadOverlay {
                return RateOfSpreadOverlayRenderer(overlay: overlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            if annotation is IgnitionAnnotation {
                let identifier = "IgnitionAnnotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                let baseConfig = NSImage.SymbolConfiguration(pointSize: 24, weight: .bold)
                let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
                let combinedConfig = baseConfig.applying(colorConfig)
                if let baseImage = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Ignition"),
                   let image = baseImage.withSymbolConfiguration(combinedConfig) {
                    view.image = image
                }
                view.canShowCallout = false
                return view
            }
            return nil
        }

        func mapView(_ mapView: ScrollZoomMKMapView, scrollZoom deltaY: CGFloat) {
            var span = mapView.region.span
            let magnitude = Double(max(0.05, min(0.6, abs(deltaY) / 300)))
            let multiplier = 1 + magnitude
            if deltaY > 0 {
                span.latitudeDelta = min(span.latitudeDelta * multiplier, 80)
                span.longitudeDelta = min(span.longitudeDelta * multiplier, 80)
            } else {
                span.latitudeDelta = max(span.latitudeDelta / multiplier, 0.0005)
                span.longitudeDelta = max(span.longitudeDelta / multiplier, 0.0005)
            }
            let newRegion = MKCoordinateRegion(center: mapView.region.center, span: span)
            isSyncingRegion = true
            mapView.setRegion(newRegion, animated: false)
            parent.region = newRegion
            isSyncingRegion = false
            mapView.refreshScale()
        }

        private func regionsEqual(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
            abs(lhs.center.latitude - rhs.center.latitude) < 0.0001 &&
            abs(lhs.center.longitude - rhs.center.longitude) < 0.0001 &&
            abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < 0.0001 &&
            abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < 0.0001
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard parent.inspectMode,
                  let mapView = gesture.view as? ScrollZoomMKMapView,
                  gesture.state == .ended else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            if let info = mapView.sampleInfo(at: coordinate) {
                parent.inspectResult = InspectResult(coordinate: info.coordinate, value: info.value)
            } else {
                parent.inspectResult = nil
            }
        }
    }
}

protocol ScrollZoomMapViewDelegate: AnyObject {
    func mapView(_ mapView: ScrollZoomMKMapView, scrollZoom deltaY: CGFloat)
}

final class ScrollZoomMKMapView: MKMapView {
    weak var scrollDelegate: ScrollZoomMapViewDelegate?
    private let scaleOverlay = MapScaleOverlay()
    private var activeOverlay: RateOfSpreadOverlay?
    private var ignitionAnnotations: [IgnitionAnnotation] = []
    private let identifyMarkerView = IdentifyMarkerView()
    private var currentIdentifyResult: InspectResult?

    override init(frame: NSRect) {
        super.init(frame: frame)
        configureAuxiliaryViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAuxiliaryViews()
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            scrollDelegate?.mapView(self, scrollZoom: event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }

    private func configureAuxiliaryViews() {
        showsCompass = false
        showsScale = false
        addSubview(scaleOverlay)
        scaleOverlay.translatesAutoresizingMaskIntoConstraints = false
        identifyMarkerView.translatesAutoresizingMaskIntoConstraints = true
        identifyMarkerView.isHidden = true
        addSubview(identifyMarkerView)

        NSLayoutConstraint.activate([
            scaleOverlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scaleOverlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        refreshScale()
    }

    override func layout() {
        super.layout()
        scaleOverlay.update(using: self)
        repositionIdentifyMarker()
    }

    func refreshScale() {
        scaleOverlay.update(using: self)
    }

    func updateOverlay(_ overlay: RateOfSpreadOverlay?) {
        if activeOverlay === overlay {
            return
        }
        if let current = activeOverlay {
            removeOverlay(current)
        }
        activeOverlay = overlay
        if let overlay {
            addOverlay(overlay)
        }
    }

    func updateIgnitionMarkers(_ markers: [IgnitionMarker]) {
        let existingCoordinates = ignitionAnnotations.map(\.coordinate)
        let newCoordinates = markers.map(\.coordinate)
        if existingCoordinates.count == newCoordinates.count &&
            zip(existingCoordinates, newCoordinates).allSatisfy({
                abs($0.latitude - $1.latitude) < 0.000001 &&
                abs($0.longitude - $1.longitude) < 0.000001
            }) {
            return
        }
        removeAnnotations(ignitionAnnotations)
        ignitionAnnotations = markers.map { IgnitionAnnotation(coordinate: $0.coordinate) }
        addAnnotations(ignitionAnnotations)
    }

    func updateIdentifyMarker(_ result: InspectResult?) {
        currentIdentifyResult = result
        guard let result else {
            identifyMarkerView.isHidden = true
            return
        }
        identifyMarkerView.isHidden = false
        identifyMarkerView.update(text: formattedRateOfSpread(result.value))
        repositionIdentifyMarker()
    }

    private func repositionIdentifyMarker() {
        guard let result = currentIdentifyResult, !identifyMarkerView.isHidden else { return }
        let point = convert(result.coordinate, toPointTo: self)
        identifyMarkerView.layoutSubtreeIfNeeded()
        let size = identifyMarkerView.intrinsicContentSize
        let clampedX = min(max(point.x - size.width / 2, 8), bounds.width - size.width - 8)
        let clampedY = min(max(point.y - size.height - 12, 8), bounds.height - size.height - 8)
        identifyMarkerView.frame = CGRect(origin: CGPoint(x: clampedX, y: clampedY),
                                          size: size)
    }

    func sampleInfo(at coordinate: CLLocationCoordinate2D) -> (value: Double, coordinate: CLLocationCoordinate2D)? {
        guard let overlay = activeOverlay,
              let sample = overlay.sample(at: coordinate) else { return nil }
        return (sample.value, sample.center)
    }
}

final class MapScaleOverlay: NSView {
    private let label = NSTextField(labelWithString: "—")
    private let bar = NSView()
    private var barWidthConstraint: NSLayoutConstraint!
    private let targetPixelLength: CGFloat = 110

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.white.cgColor
        bar.layer?.cornerRadius = 1.5

        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.alignment = .right
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bar)
        addSubview(label)

        barWidthConstraint = bar.widthAnchor.constraint(equalToConstant: targetPixelLength)

        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            bar.heightAnchor.constraint(equalToConstant: 3),
            barWidthConstraint,
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            label.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(using mapView: MKMapView) {
        guard mapView.bounds.width > 0 else { return }
        let mapRect = mapView.visibleMapRect
        guard mapRect.size.width > 0 else { return }
        let left = MKMapPoint(x: mapRect.minX, y: mapRect.midY)
        let right = MKMapPoint(x: mapRect.maxX, y: mapRect.midY)
        let totalMeters = left.distance(to: right)
        guard totalMeters.isFinite else { return }

        let metersPerPoint = totalMeters / Double(mapView.bounds.width)
        let desiredMeters = metersPerPoint * Double(targetPixelLength)
        let scaledValue = niceScaleValue(for: desiredMeters)
        let units = scaledValue >= 1000 ? "km" : "m"
        let displayValue = scaledValue >= 1000 ? scaledValue / 1000 : scaledValue
        if units == "m" {
            label.stringValue = "\(Int(displayValue)) m"
        } else {
            let shown = displayValue >= 10 ? String(format: "%.0f", displayValue) : String(format: "%.1f", displayValue)
            label.stringValue = "\(shown) km"
        }

        let width = CGFloat(scaledValue / metersPerPoint)
        barWidthConstraint.constant = max(24, min(width, mapView.bounds.width - 40))
        needsLayout = true
    }

    private func niceScaleValue(for meters: Double) -> Double {
        guard meters > 0 else { return 1 }
        let exponent = floor(log10(meters))
        let base = pow(10.0, exponent)
        let normalized = meters / base
        let candidate: Double
        if normalized < 2 { candidate = 1 }
        else if normalized < 5 { candidate = 2 }
        else { candidate = 5 }
        return candidate * base
    }
}

final class IdentifyMarkerView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let container = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.95).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        container.layer?.borderWidth = 1.2
        container.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        container.addSubview(label)
        addSubview(dot)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            dot.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 5),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
            dot.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String) {
        label.stringValue = text
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: max(90, labelSize.width + 20), height: labelSize.height + 8 + 12 + 6)
    }
}

private let rosIdentifyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.usesGroupingSeparator = false
    return formatter
}()

private func formattedRateOfSpread(_ value: Double) -> String {
    if let string = rosIdentifyFormatter.string(from: NSNumber(value: value)) {
        return "\(string) m/min"
    }
    return String(format: "%.2f m/min", locale: Locale(identifier: "en_US_POSIX"), value)
}

final class MapController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    weak var mapView: ScrollZoomMKMapView?

    func resetHeading() {
        guard let mapView else { return }
        let camera = mapView.camera
        camera.heading = 0
        mapView.setCamera(camera, animated: true)
    }

    func clearOverlay() {
        mapView?.updateOverlay(nil)
    }
}
#endif
