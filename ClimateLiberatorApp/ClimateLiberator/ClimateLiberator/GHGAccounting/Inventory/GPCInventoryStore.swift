import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// GPC inventories (one JSON file each) and their exports.
///
/// Nothing is written to disk without the user asking: new inventories, loaded
/// examples and edits stay in memory, marked unsaved, until the user chooses Save
/// (⌘S) or confirms saving when the app quits.
@MainActor
final class GPCInventoryStore: ObservableObject {
    @Published private(set) var inventories: [GPCInventory] = []
    @Published var selectedID: UUID?
    @Published var statusMessage = ""
    /// Inventories whose current state is not on disk (new, edited or upgraded).
    @Published private(set) var unsavedIDs: Set<UUID> = []

    let locations: GHGDataLocations
    private let persists: Bool
    /// Inventories that have a file on disk.
    private var savedIDs: Set<UUID> = []

    /// The app's store, consulted before quitting. Tests create their own stores.
    static weak var active: GPCInventoryStore?

    init(locations: GHGDataLocations = .current, loadFromDisk: Bool = true) {
        self.locations = locations
        self.persists = loadFromDisk
        if loadFromDisk {
            load()
            if Self.active == nil { Self.active = self }
        }
        selectedID = inventories.first?.id
    }

    var selected: GPCInventory? {
        guard let selectedID else { return nil }
        return inventories.first { $0.id == selectedID }
    }

    var hasUnsavedChanges: Bool { !unsavedIDs.isEmpty }
    var unsavedInventories: [GPCInventory] { inventories.filter { unsavedIDs.contains($0.id) } }
    func isUnsaved(_ id: UUID) -> Bool { unsavedIDs.contains(id) }
    func isOnDisk(_ id: UUID) -> Bool { savedIDs.contains(id) }

    // MARK: Editing

    @discardableResult
    func createInventory(cityName: String, year: Int) -> GPCInventory {
        let inventory = GPCInventory(cityName: cityName, inventoryYear: year)
        inventories.insert(inventory, at: 0)
        selectedID = inventory.id
        unsavedIDs.insert(inventory.id)
        statusMessage = "Created \(inventory.displayName). It is not saved until you choose Save (⌘S)."
        return inventory
    }

    /// Adds a copy of a worked example with fresh IDs, so it can be loaded more than once.
    func loadExample(_ example: GPCInventory) {
        var copy = example
        copy.id = UUID()
        copy.entries = copy.entries.map { entry in
            var fresh = entry
            fresh.id = UUID()
            return fresh
        }
        copy.createdAt = Date()
        copy.updatedAt = Date()
        inventories.insert(copy, at: 0)
        selectedID = copy.id
        unsavedIDs.insert(copy.id)
        statusMessage = "Loaded the \(copy.cityName) example (not saved). Its numbers are illustrative estimates — see each entry's source."
    }

    /// Replaces the inventory in memory and marks it unsaved.
    func update(_ inventory: GPCInventory) {
        guard let index = inventories.firstIndex(where: { $0.id == inventory.id }) else { return }
        var updated = inventory
        updated.updatedAt = Date()
        inventories[index] = updated
        unsavedIDs.insert(updated.id)
    }

    func mutateSelected(_ change: (inout GPCInventory) -> Void) {
        guard var inventory = selected else { return }
        change(&inventory)
        update(inventory)
    }

    func upsertEntry(_ entry: GPCInventoryEntry) {
        mutateSelected { inventory in
            if let index = inventory.entries.firstIndex(where: { $0.id == entry.id }) { inventory.entries[index] = entry }
            else { inventory.entries.append(entry) }
        }
    }

    func removeEntry(id: UUID) {
        mutateSelected { $0.entries.removeAll { $0.id == id } }
    }

    /// Removes an inventory. A saved file goes to the Trash so it can be recovered;
    /// an inventory that was never saved is simply discarded.
    func deleteInventory(id: UUID) {
        guard let inventory = inventories.first(where: { $0.id == id }) else { return }
        let wasOnDisk = savedIDs.contains(id)
        unsavedIDs.remove(id)
        savedIDs.remove(id)
        inventories.removeAll { $0.id == id }
        if persists, wasOnDisk {
            try? FileManager.default.trashItem(at: fileURL(for: id), resultingItemURL: nil)
        }
        if selectedID == id { selectedID = inventories.first?.id }
        statusMessage = wasOnDisk ? "Moved \(inventory.displayName) to the Trash." : "Discarded \(inventory.displayName)."
    }

    // MARK: Saving

    /// Writes one inventory to disk. Returns false if the write failed.
    @discardableResult
    func save(id: UUID) -> Bool {
        guard let inventory = inventories.first(where: { $0.id == id }) else { return false }
        guard persists else { unsavedIDs.remove(id); return true }
        do {
            try GHGJSON.write(inventory, to: fileURL(for: id))
            unsavedIDs.remove(id)
            savedIDs.insert(id)
            statusMessage = "Saved \(inventory.displayName)."
            return true
        } catch {
            statusMessage = "Could not save \(inventory.displayName): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveSelected() -> Bool {
        guard let selectedID else { return false }
        return save(id: selectedID)
    }

    /// Saves every unsaved inventory. Returns false if any write failed.
    @discardableResult
    func saveAll() -> Bool {
        unsavedIDs.map { save(id: $0) }.allSatisfy { $0 }
    }

    /// Drops unsaved changes: reloads the saved copy, or removes a never-saved inventory.
    func revert(id: UUID) {
        guard unsavedIDs.contains(id) else { return }
        if persists, savedIDs.contains(id),
           let saved = try? GHGJSON.read(GPCInventory.self, from: fileURL(for: id)),
           let index = inventories.firstIndex(where: { $0.id == id }) {
            inventories[index] = saved
            unsavedIDs.remove(id)
            statusMessage = "Reverted \(saved.displayName) to the saved version."
        } else {
            deleteInventory(id: id)
        }
    }

    // MARK: Boundary files

    func importBoundary(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let polygon: BoundaryPolygon
            if url.pathExtension.lowercased() == "kml" {
                polygon = try BoundaryFileCodec.polygon(fromKML: data)
            } else {
                polygon = try BoundaryFileCodec.polygon(fromGeoJSON: data)
            }
            mutateSelected { inventory in
                inventory.boundary = polygon
                if inventory.boundarySource.isEmpty { inventory.boundarySource = url.lastPathComponent }
            }
            let area = String(format: "%.2f", polygon.areaSquareKilometres)
            statusMessage = "Imported \(polygon.vertices.count) boundary points (\(area) km²) from \(url.lastPathComponent)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Uses an OpenStreetMap outline as the inventory boundary and records its source and licence.
    func applyPlaceBoundary(_ place: PlaceBoundaryResult) {
        guard let polygon = place.boundary else { return }
        mutateSelected { inventory in
            inventory.boundary = polygon
            inventory.boundarySource = place.sourceDescription
            if place.isAdministrative { inventory.boundaryType = .administrative }
            if inventory.cityName.trimmingCharacters(in: .whitespaces).isEmpty { inventory.cityName = place.name }
        }
        let area = String(format: "%.2f", polygon.areaSquareKilometres)
        let parts = place.partCount > 1 ? " Used the largest of \(place.partCount) parts." : ""
        statusMessage = "Boundary set to \(place.name): \(polygon.vertices.count) points, \(area) km².\(parts) Check it against the official map."
    }

    /// Saves the selected boundary as GeoJSON (EPSG:4326) where the user chooses.
    func exportBoundaryGeoJSON() {
        guard let inventory = selected, inventory.boundary.isClosed else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "geojson", conformingTo: .json) ?? .json]
        let city = inventory.cityName.isEmpty ? "boundary" : inventory.cityName
        panel.nameFieldStringValue = "\(city.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-"))-boundary.geojson"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BoundaryFileCodec.geoJSON(inventory.boundary, properties: [
                "name": inventory.cityName, "inventory_year": inventory.inventoryYear,
                "boundary_type": inventory.boundaryType.title, "source": inventory.boundarySource,
            ])
            try data.write(to: url, options: .atomic)
            statusMessage = "Saved boundary to \(url.lastPathComponent)."
        } catch {
            statusMessage = "Could not save the boundary: \(error.localizedDescription)"
        }
    }

    // MARK: Exports

    func exportReports() {
        guard let inventory = selected else { return }
        do {
            let folder = try exportFolder(for: inventory)
            let summary = GPCInventorySummary.make(inventory)
            try GPCReportExporter.entriesCSV(inventory, summary: summary)
                .write(to: folder.appendingPathComponent("gpc_entries.csv"), atomically: true, encoding: .utf8)
            try GPCReportExporter.summaryCSV(inventory, summary: summary)
                .write(to: folder.appendingPathComponent("gpc_summary.csv"), atomically: true, encoding: .utf8)
            try GHGJSON.write(inventory, to: folder.appendingPathComponent("inventory.json"))
            if inventory.boundary.vertices.count >= 3 {
                let geojson = try BoundaryFileCodec.geoJSON(inventory.boundary, properties: [
                    "name": inventory.cityName, "inventory_year": inventory.inventoryYear,
                    "boundary_type": inventory.boundaryType.title, "source": inventory.boundarySource,
                ])
                try geojson.write(to: folder.appendingPathComponent("boundary.geojson"), options: .atomic)
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            statusMessage = "Exported GPC tables, inventory JSON and boundary to \(folder.path)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Writes the scenario's action plan and pathway as CSV, beside the GPC exports.
    func exportActionPlan(scenarioID: UUID) {
        guard let inventory = selected,
              let scenario = inventory.decarbonizationScenarios.first(where: { $0.id == scenarioID }) else { return }
        do {
            let folder = try exportFolder(for: inventory)
            let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: GPCInventorySummary.make(inventory))
            let projection = DecarbonizationEngine.project(baseline, scenario: scenario)
            try ActionPlanAnalysis.csv(scenario, result: projection.target)
                .write(to: folder.appendingPathComponent("action_plan.csv"), atomically: true, encoding: .utf8)
            try ActionPlanAnalysis.pathwayCSV(projection)
                .write(to: folder.appendingPathComponent("pathway.csv"), atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            statusMessage = "Exported the action plan and pathway for \(scenario.name) to \(folder.path)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportFolder(for inventory: GPCInventory) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let city = inventory.cityName.isEmpty ? "city" : inventory.cityName
        let safe = city.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let folder = locations.exportsDirectory
            .appendingPathComponent("\(safe)-\(inventory.inventoryYear)-\(formatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: Persistence

    private func fileURL(for id: UUID) -> URL {
        locations.inventoriesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func load() {
        let directory = locations.inventoriesDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [GPCInventory] = []
        var failures = 0
        for file in files where file.pathExtension == "json" {
            guard var inventory = try? GHGJSON.read(GPCInventory.self, from: file) else { failures += 1; continue }
            savedIDs.insert(inventory.id)
            // The upgrade is offered, not written: the user saves it like any other change.
            if GPCExampleInventories.upgradeLegacyIrittyBoundary(&inventory) { unsavedIDs.insert(inventory.id) }
            loaded.append(inventory)
        }
        inventories = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if failures > 0 { statusMessage = "\(failures) inventory file(s) could not be read and were skipped." }
    }
}
