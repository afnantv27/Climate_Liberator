import Foundation
import Combine

/// Reduction plans (targets, measures, credits), one per client. Like every store,
/// edits stay in memory until saved and quitting asks about unsaved plans.
@MainActor
final class ReductionStore: ObservableObject {
    @Published private(set) var plans: [UUID: ReductionPlan] = [:]
    @Published private(set) var unsavedIDs: Set<UUID> = []
    @Published var statusMessage = ""

    let folder: JSONDocumentFolder<ReductionPlan>
    private let persists: Bool

    init(folder: JSONDocumentFolder<ReductionPlan> = .appData("Reduce"), loadFromDisk: Bool = true) {
        self.folder = folder
        self.persists = loadFromDisk
        if loadFromDisk {
            load()
            UnsavedWorkRegistry.register(self)
        }
    }

    /// The client's plan, or an empty one (not stored until something is added).
    func plan(for clientID: UUID, clientName: String = "") -> ReductionPlan {
        plans[clientID] ?? ReductionPlan(clientID: clientID, clientName: clientName)
    }

    func isUnsaved(_ clientID: UUID) -> Bool { unsavedIDs.contains(clientID) }

    // MARK: Editing

    /// Applies a change; unchanged results are ignored so bindings don't mark plans unsaved.
    func update(_ clientID: UUID, clientName: String, _ change: (inout ReductionPlan) -> Void) {
        let old = plan(for: clientID, clientName: clientName)
        var plan = old
        change(&plan)
        plan.clientName = clientName.isEmpty ? plan.clientName : clientName
        guard plan != old else { return }
        plan.updatedAt = Date()
        plans[clientID] = plan
        unsavedIDs.insert(clientID)
    }

    func upsertTarget(_ target: ReductionTarget, client: UUID, name: String) {
        update(client, clientName: name) { plan in
            if let index = plan.targets.firstIndex(where: { $0.id == target.id }) { plan.targets[index] = target }
            else { plan.targets.append(target) }
        }
    }

    func removeTarget(_ id: UUID, client: UUID, name: String) {
        update(client, clientName: name) { $0.targets.removeAll { $0.id == id } }
    }

    func upsertMeasure(_ measure: ReductionMeasure, client: UUID, name: String) {
        update(client, clientName: name) { plan in
            if let index = plan.measures.firstIndex(where: { $0.id == measure.id }) { plan.measures[index] = measure }
            else { plan.measures.append(measure) }
        }
    }

    func removeMeasure(_ id: UUID, client: UUID, name: String) {
        update(client, clientName: name) { $0.measures.removeAll { $0.id == id } }
    }

    func upsertCredit(_ credit: CarbonCredit, client: UUID, name: String) {
        update(client, clientName: name) { plan in
            if let index = plan.credits.firstIndex(where: { $0.id == credit.id }) { plan.credits[index] = credit }
            else { plan.credits.append(credit) }
        }
    }

    func removeCredit(_ id: UUID, client: UUID, name: String) {
        update(client, clientName: name) { $0.credits.removeAll { $0.id == id } }
    }

    // MARK: Saving

    @discardableResult
    func save(clientID: UUID) -> Bool {
        guard let plan = plans[clientID] else { return false }
        guard persists else {
            unsavedIDs.remove(clientID)
            return true
        }
        do {
            try folder.write(plan)
            unsavedIDs.remove(clientID)
            statusMessage = "Saved the reduction plan for \(plan.clientName)."
            return true
        } catch {
            statusMessage = "Could not save the plan for \(plan.clientName): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveAll() -> Bool {
        unsavedIDs.reduce(true) { ok, id in save(clientID: id) && ok }
    }

    func revert(clientID: UUID) {
        if persists, folder.exists(clientID), let saved = try? folder.read(folder.fileURL(clientID)) {
            plans[clientID] = saved
        } else {
            plans[clientID] = nil
        }
        unsavedIDs.remove(clientID)
    }

    private func load() {
        let result = folder.loadAll()
        plans = Dictionary(result.documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !result.unreadable.isEmpty {
            statusMessage = "\(result.unreadable.count) reduction plan file(s) could not be read and were skipped."
        }
    }
}

extension ReductionStore: UnsavedWorkProviding {
    var unsavedWorkKind: String { "Reduction plans" }
    var unsavedItemNames: [String] {
        unsavedIDs.compactMap { plans[$0].map { $0.clientName.isEmpty ? "Untitled client" : $0.clientName } }.sorted()
    }
    func saveAllUnsavedWork() -> Bool { saveAll() }
    var unsavedWorkStatus: String { statusMessage }
}
