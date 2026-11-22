import SwiftUI
import MapKit
import UniformTypeIdentifiers

private enum BoundaryEditMode: String, CaseIterable, Identifiable {
    case navigate, draw, facility
    var id: String { rawValue }
    var title: String {
        switch self {
        case .navigate: return "Navigate"
        case .draw: return "Draw"
        case .facility: return "Facility"
        }
    }
}

/// Step 1: find, draw or import the inventory boundary, then record city details.
struct GPCBoundaryEditorView: View {
    @ObservedObject var store: GPCInventoryStore
    let inventory: GPCInventory
    let accent: Color

    /// Fill and outline of the chosen area.
    static let chosenColor = Color.green
    /// Above this many points the numbered handles are hidden (imported outlines).
    private static let maxVertexHandles = 80
    private static let maxListedPoints = 200
    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 11.9819, longitude: 75.6703),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25))

    @State private var mode: BoundaryEditMode = .navigate
    @State private var camera: MapCameraPosition = .region(GPCBoundaryEditorView.defaultRegion)
    @State private var useSatellite = false
    @State private var facilityName = "Landfill"
    @State private var populationText = ""
    @State private var fittedInventoryID: UUID?
    @State private var importingFile = false
    @State private var confirmingClear = false
    @State private var showingPoints = false
    /// Validation runs off the main thread (the crossing check is O(n²)); nil while checking.
    @State private var boundaryIssues: [String]?

    // OpenStreetMap place lookup
    @State private var placeQuery = ""
    @State private var results: [PlaceBoundaryResult] = []
    @State private var selectedResultID: String?
    @State private var searching = false
    @State private var lookupMessage = ""
    @State private var lastLookup = Date.distantPast
    private let lookup = BoundaryLookupService()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                mapToolbar
                map
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .bottomLeading) { mapHint }
                    .overlay(alignment: .bottomTrailing) { attributionBadge }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    findCard
                    boundaryCard
                    metadataCard
                    facilitiesCard
                    pointsCard
                }
            }
            .frame(width: 380)
        }
        .onAppear(perform: fitIfNeeded)
        .onChange(of: inventory.id) { _, _ in fitIfNeeded() }
        .task(id: inventory.boundary) {
            let boundary = inventory.boundary
            let issues = await Task.detached(priority: .userInitiated) { boundary.validationIssues }.value
            if !Task.isCancelled { boundaryIssues = issues }
        }
        .fileImporter(isPresented: $importingFile,
                      allowedContentTypes: [.json, UTType(filenameExtension: "geojson") ?? .json,
                                            UTType(filenameExtension: "kml") ?? .xml],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            store.importBoundary(from: url)
            mode = .navigate
            fit(store.selected?.boundary)
        }
        .confirmationDialog("Clear the \(inventory.boundary.vertices.count)-point boundary?", isPresented: $confirmingClear) {
            Button("Clear Boundary", role: .destructive, action: clearBoundary)
        }
    }

    // MARK: Map

    private var selectedResult: PlaceBoundaryResult? { results.first { $0.id == selectedResultID } }

    private var map: some View {
        let chosen = inventory.boundary.vertices.map(\.clCoordinate)
        let preview = selectedResult
        let previewOutline: [CLLocationCoordinate2D]? = preview?.boundary.flatMap { outline in
            outline == inventory.boundary ? nil : outline.vertices.map(\.clCoordinate)
        }
        let showHandles = mode == .draw && chosen.count <= Self.maxVertexHandles
        return MapReader { proxy in
            Map(position: $camera) {
                if chosen.count >= 3 {
                    MapPolygon(coordinates: chosen)
                        .foregroundStyle(Self.chosenColor.opacity(0.25))
                        .stroke(Self.chosenColor, lineWidth: 2)
                } else if chosen.count == 2 {
                    MapPolyline(coordinates: chosen)
                        .stroke(Self.chosenColor, lineWidth: 2)
                }
                if let previewOutline {
                    MapPolygon(coordinates: previewOutline)
                        .foregroundStyle(Self.chosenColor.opacity(0.08))
                        .stroke(Self.chosenColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                if let preview, !preview.hasBoundary {
                    Marker(preview.name, systemImage: "mappin", coordinate: preview.center.clCoordinate)
                }
                if showHandles {
                    ForEach(Array(chosen.enumerated()), id: \.offset) { index, coordinate in
                        Annotation("", coordinate: coordinate) { vertexHandle(index) }
                    }
                }
                ForEach(inventory.facilities) { facility in
                    Marker(facility.name, systemImage: "building.2.fill", coordinate: facility.coordinate.clCoordinate)
                        .tint(inventory.boundary.contains(facility.coordinate) ? Color.green : Color.orange)
                }
            }
            .mapStyle(useSatellite ? .hybrid : .standard)
            .onTapGesture { location in
                guard mode != .navigate, let coordinate = proxy.convert(location, from: .local) else { return }
                handleTap(GeoCoordinate(coordinate))
            }
        }
        .frame(minHeight: 480)
    }

    private func vertexHandle(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Self.chosenColor))
            .overlay(Circle().stroke(.white, lineWidth: 1))
    }

    private var mapToolbar: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(BoundaryEditMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            if mode == .facility {
                TextField("Facility name", text: $facilityName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
            }
            Spacer()
            Toggle("Satellite", isOn: $useSatellite).toggleStyle(.switch).controlSize(.small)
            Button { fit(inventory.boundary) } label: { Label("Fit", systemImage: "scope") }
                .disabled(inventory.boundary.isEmpty)
                .help("Zoom to the boundary")
        }
    }

    private var mapHint: some View {
        let count = inventory.boundary.vertices.count
        let text: String
        switch mode {
        case .navigate:
            text = "Search a place on the right, or switch to Draw to click points."
        case .draw:
            text = count > Self.maxVertexHandles
                ? "Clicks add points after point \(count). To draw a new outline, clear this one first."
                : "Click to add boundary points in order. Undo removes the last point."
        case .facility:
            text = "Click to place \"\(facilityName)\". Green = inside boundary, orange = outside."
        }
        return Text(text)
            .font(.caption)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(12)
    }

    @ViewBuilder
    private var attributionBadge: some View {
        if selectedResult?.hasBoundary == true || inventory.boundarySource.contains("OpenStreetMap") {
            Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                .font(.caption2)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(12)
        }
    }

    private func handleTap(_ coordinate: GeoCoordinate) {
        switch mode {
        case .draw:
            store.mutateSelected { $0.boundary.vertices.append(coordinate) }
        case .facility:
            let name = facilityName.trimmingCharacters(in: .whitespaces)
            store.mutateSelected { inventory in
                inventory.facilities.append(GPCFacility(name: name.isEmpty ? "Facility" : name, coordinate: coordinate))
            }
        case .navigate:
            break
        }
    }

    // MARK: Camera

    private func fitIfNeeded() {
        guard fittedInventoryID != inventory.id else { return }
        fittedInventoryID = inventory.id
        populationText = inventory.population.map(String.init) ?? ""
        if inventory.boundary.isEmpty { camera = .region(Self.defaultRegion) } else { fit(inventory.boundary) }
    }

    private func fit(_ boundary: BoundaryPolygon?) {
        guard let box = boundary?.boundingBox else { return }
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (box.maxLatitude - box.minLatitude) * 1.4),
                                    longitudeDelta: max(0.01, (box.maxLongitude - box.minLongitude) * 1.4))
        let center = CLLocationCoordinate2D(latitude: (box.minLatitude + box.maxLatitude) / 2,
                                            longitude: (box.minLongitude + box.maxLongitude) / 2)
        withAnimation { camera = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    private func centre(on coordinate: GeoCoordinate) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: coordinate.clCoordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
        }
    }

    // MARK: Place lookup

    private var findCard: some View {
        GHGPanelCard(title: "Find Boundary", subtitle: "Search OpenStreetMap for a municipality, district or ward and use its outline.") {
            HStack(spacing: 8) {
                TextField("e.g. Iritty, Kerala", text: $placeQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await runLookup() } }
                Button { Task { await runLookup() } } label: {
                    if searching { ProgressView().controlSize(.small) } else { Text("Search") }
                }
                .disabled(searching || placeQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !lookupMessage.isEmpty {
                Text(lookupMessage).font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            if !results.isEmpty {
                VStack(spacing: 6) {
                    ForEach(results) { resultRow($0) }
                }
            }
            if let result = selectedResult {
                selectedResultActions(result)
            }
            Text("\(BoundaryLookupService.attribution). Outlines are community-mapped: check them against the official map.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func resultRow(_ result: PlaceBoundaryResult) -> some View {
        let isSelected = result.id == selectedResultID
        return Button { select(result) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.hasBoundary ? "square.dashed.inset.filled" : "mappin.circle")
                    .foregroundStyle(result.hasBoundary ? Self.chosenColor : Color.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.name).font(.callout.weight(.semibold))
                        if !result.kind.isEmpty { GHGTag(text: result.kind.capitalized) }
                    }
                    Text(result.displayName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                    Text(result.boundary.map { String(format: "Outline: %.2f km², %d points", $0.areaSquareKilometres, $0.vertices.count) }
                         ?? "Point only — no outline in OpenStreetMap")
                        .font(.caption2)
                        .foregroundStyle(result.hasBoundary ? Self.chosenColor : Color.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Self.chosenColor.opacity(0.18) : Color.white.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectedResultActions(_ result: PlaceBoundaryResult) -> some View {
        let isCurrent = result.boundary != nil && result.boundary == inventory.boundary
        HStack(spacing: 8) {
            if result.hasBoundary {
                Button { importPlace(result) } label: {
                    Label(isCurrent ? "In Use" : "Import Boundary", systemImage: isCurrent ? "checkmark" : "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.chosenColor)
                .disabled(isCurrent)
            } else {
                Button("Centre Map Here") { centre(on: result.center) }
            }
            Spacer()
            if let url = result.osmURL { Link("View on OSM", destination: url).font(.caption) }
        }
        if result.partCount > 1 {
            Text("OSM maps \(result.partCount) separate parts for this place; the largest is used.")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        if result.hasBoundary, !isCurrent, inventory.boundary.isClosed {
            Text("Importing replaces the current \(inventory.boundary.vertices.count)-point boundary.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func runLookup() async {
        let query = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searching else { return }
        searching = true
        defer { searching = false }
        // Nominatim policy: at most one request per second.
        let wait = 1.0 - Date().timeIntervalSince(lastLookup)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        lastLookup = Date()
        do {
            let found = try await lookup.search(query)
            results = found
            selectedResultID = nil
            if let first = found.first { select(first) }
            if found.isEmpty {
                lookupMessage = "No places found for \"\(query)\". Add the district or state, e.g. \"Iritty, Kannur, Kerala\"."
            } else if !found.contains(where: \.hasBoundary) {
                lookupMessage = "OpenStreetMap has no outline for these results. Draw the boundary or import a file."
            } else {
                lookupMessage = ""
            }
        } catch {
            lookupMessage = error.localizedDescription
        }
    }

    private func select(_ result: PlaceBoundaryResult) {
        selectedResultID = result.id
        if let boundary = result.boundary { fit(boundary) } else { centre(on: result.center) }
    }

    private func importPlace(_ result: PlaceBoundaryResult) {
        store.applyPlaceBoundary(result)
        mode = .navigate
        fit(result.boundary)
    }

    // MARK: Side panel

    private var boundaryCard: some View {
        let boundary = inventory.boundary
        return GHGPanelCard(title: "Boundary", subtitle: "GPC: use the administrative or planning area you report for.") {
            HStack {
                GHGMetricCard(title: "Area", value: String(format: "%.2f km²", boundary.areaSquareKilometres),
                              detail: "\(boundary.vertices.count) points")
                GHGMetricCard(title: "Perimeter", value: String(format: "%.1f km", boundary.perimeterMetres() / 1_000),
                              detail: "Great-circle")
            }
            validationLabels
            HStack(spacing: 8) {
                Button("Import File…") { importingFile = true }
                    .help("GeoJSON (Polygon/MultiPolygon, EPSG:4326) or KML from Google Earth / QGIS")
                Button("Export GeoJSON…") { store.exportBoundaryGeoJSON() }
                    .disabled(!boundary.isClosed)
                Spacer()
                Button { store.mutateSelected { _ = $0.boundary.vertices.popLast() } } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Remove the last point")
                .disabled(boundary.isEmpty)
                Button(role: .destructive) {
                    if boundary.vertices.count > 10 { confirmingClear = true } else { clearBoundary() }
                } label: { Image(systemName: "trash") }
                .help("Clear the boundary")
                .disabled(boundary.isEmpty)
            }
            Text("Area is on the WGS84 ellipsoid (authalic-latitude method, within ~0.01% of geodesic area).")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private var validationLabels: some View {
        if let issues = boundaryIssues {
            if issues.isEmpty {
                Label("Boundary is closed and valid.", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            ForEach(issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if inventory.boundary.vertices.count > BoundaryPolygon.maxVerticesForCrossingCheck {
                Text("Crossing check skipped above \(BoundaryPolygon.maxVerticesForCrossingCheck) points.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        } else {
            Label("Checking boundary…", systemImage: "hourglass").font(.caption)
        }
    }

    private func clearBoundary() {
        store.mutateSelected { inventory in
            inventory.boundary.vertices.removeAll()
            if inventory.boundarySource.hasPrefix("OpenStreetMap") { inventory.boundarySource = "" }
        }
    }

    private var metadataCard: some View {
        GHGPanelCard(title: "City Details", subtitle: "Reported with the inventory (GPC Table 4.1).") {
            VStack(alignment: .leading, spacing: 8) {
                labeledField("City / town", text: binding(\.cityName))
                labeledField("State / region", text: binding(\.region))
                labeledField("Country", text: binding(\.country))
                Stepper(value: binding(\.inventoryYear), in: 1990...2100) {
                    Text("Inventory year: \(String(inventory.inventoryYear))").font(.callout)
                }
                HStack {
                    Text("Population").font(.callout)
                    TextField("e.g. 130000", text: $populationText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: populationText) { _, value in
                            let population = Int(value.filter(\.isNumber))
                            guard population != store.selected?.population else { return }
                            store.mutateSelected { $0.population = population }
                        }
                }
                Picker("Boundary type", selection: binding(\.boundaryType)) {
                    ForEach(GPCBoundaryType.allCases) { Text($0.title).tag($0) }
                }
                labeledField("Boundary source", text: binding(\.boundarySource))
                Text("Filled automatically for OpenStreetMap and file imports. Otherwise say where the outline came from, e.g. \"Municipality ward map 2021\".")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var facilitiesCard: some View {
        GHGPanelCard(title: "Facilities", subtitle: "Landfills, STPs, power plants. Inside/outside decides the GPC scope (e.g. waste III.x.1 vs III.x.2).") {
            if inventory.facilities.isEmpty {
                Text("Switch the map to Facility and click to place one.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(inventory.facilities) { facility in
                let inside = inventory.boundary.contains(facility.coordinate)
                HStack {
                    Image(systemName: "building.2.fill").foregroundStyle(inside ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text(facility.name).font(.callout)
                        Text(inside ? "Inside boundary" : "Outside boundary")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button {
                        store.mutateSelected { $0.facilities.removeAll { $0.id == facility.id } }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var pointsCard: some View {
        let points = inventory.boundary.vertices
        return GHGPanelCard(title: "Points", subtitle: "Latitude, longitude (WGS84).") {
            DisclosureGroup(isExpanded: $showingPoints) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(points.prefix(Self.maxListedPoints).enumerated()), id: \.offset) { index, vertex in
                        HStack {
                            Text("\(index + 1)").font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                            Text(String(format: "%.5f, %.5f", vertex.latitude, vertex.longitude))
                                .font(.caption.monospacedDigit())
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                store.mutateSelected { inventory in
                                    guard inventory.boundary.vertices.indices.contains(index) else { return }
                                    inventory.boundary.vertices.remove(at: index)
                                }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                    if points.count > Self.maxListedPoints {
                        Text("…and \(points.count - Self.maxListedPoints) more. Export GeoJSON for the full list.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(points.isEmpty ? "No points yet" : "\(points.count) points").font(.callout)
            }
            .disabled(points.isEmpty)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).font(.callout).frame(width: 110, alignment: .leading)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<GPCInventory, Value>) -> Binding<Value> {
        Binding(
            get: { (store.selected ?? inventory)[keyPath: keyPath] },
            set: { value in store.mutateSelected { $0[keyPath: keyPath] = value } }
        )
    }
}
