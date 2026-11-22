import Foundation
import Combine

/// The client register in memory. Edits stay in memory until the user saves;
/// quitting with unsaved clients asks first (see `UnsavedWorkGuard`).
@MainActor
final class ClientRegistryStore: ObservableObject {
    @Published private(set) var clients: [Client] = []
    @Published var selectedID: UUID?
    @Published private(set) var unsavedIDs: Set<UUID> = []
    @Published var statusMessage = ""

    let folder: JSONDocumentFolder<Client>
    private let persists: Bool

    init(folder: JSONDocumentFolder<Client> = .appData("Clients"), loadFromDisk: Bool = true) {
        self.folder = folder
        self.persists = loadFromDisk
        if loadFromDisk {
            load()
            UnsavedWorkRegistry.register(self)
        }
        selectedID = clients.first?.id
    }

    // MARK: Reading

    func client(_ id: UUID?) -> Client? {
        guard let id else { return nil }
        return clients.first { $0.id == id }
    }

    var selectedClient: Client? { client(selectedID) }
    var unsavedClients: [Client] { clients.filter { unsavedIDs.contains($0.id) } }
    func isUnsaved(_ id: UUID) -> Bool { unsavedIDs.contains(id) }

    /// Cluster names in use, sorted; spelling differences in case are merged.
    var clusters: [String] {
        var seen: [String: String] = [:]
        for name in clients.map(\.clusterName) where !name.isEmpty {
            seen[name.lowercased()] = seen[name.lowercased()] ?? name
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func clients(inCluster name: String) -> [Client] {
        clients.filter { $0.clusterName.caseInsensitiveCompare(name) == .orderedSame }
    }

    var siteCount: Int { clients.reduce(0) { $0 + $1.sites.count } }

    // MARK: Editing

    @discardableResult
    func createClient(name: String = "", cluster: String = "") -> Client {
        var client = Client(name: name)
        client.cluster = cluster
        insert(client)
        statusMessage = "Added \(client.displayName) (not saved)."
        return client
    }

    /// Applies a change; no-op writes (bindings echoing a value) are ignored.
    func update(_ id: UUID, _ change: (inout Client) -> Void) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        var client = clients[index]
        change(&client)
        guard client != clients[index] else { return }
        client.updatedAt = Date()
        clients[index] = client
        unsavedIDs.insert(id)
    }

    @discardableResult
    func addSite(to clientID: UUID, name: String = "") -> Site? {
        guard client(clientID) != nil else { return nil }
        let site = Site(name: name)
        update(clientID) { $0.sites.append(site) }
        return site
    }

    func updateSite(_ siteID: UUID, of clientID: UUID, _ change: (inout Site) -> Void) {
        update(clientID) { client in
            guard let index = client.sites.firstIndex(where: { $0.id == siteID }) else { return }
            change(&client.sites[index])
        }
    }

    func removeSite(_ siteID: UUID, from clientID: UUID) {
        update(clientID) { $0.sites.removeAll { $0.id == siteID } }
    }

    // MARK: Saving

    @discardableResult
    func save(id: UUID) -> Bool {
        guard let client = client(id) else { return false }
        guard persists else {
            unsavedIDs.remove(id)
            return true
        }
        do {
            try folder.write(client)
            unsavedIDs.remove(id)
            statusMessage = "Saved \(client.displayName)."
            return true
        } catch {
            statusMessage = "Could not save \(client.displayName): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveAll() -> Bool {
        unsavedIDs.reduce(true) { ok, id in save(id: id) && ok }
    }

    /// Restores the saved file, or removes a client that was never saved.
    func revert(id: UUID) {
        guard let index = clients.firstIndex(where: { $0.id == id }) else { return }
        if persists, folder.exists(id), let saved = try? folder.read(folder.fileURL(id)) {
            clients[index] = saved
        } else {
            clients.remove(at: index)
            if selectedID == id { selectedID = clients.first?.id }
        }
        unsavedIDs.remove(id)
    }

    /// Removes the client; its file goes to the Trash. Linked engagements and plans
    /// keep their data and simply show as unlinked.
    func delete(id: UUID) {
        guard let client = client(id) else { return }
        do {
            if persists { try folder.trash(id) }
            clients.removeAll { $0.id == id }
            unsavedIDs.remove(id)
            if selectedID == id { selectedID = clients.first?.id }
            statusMessage = "Moved \(client.displayName) to the Trash."
        } catch {
            statusMessage = "Could not delete \(client.displayName): \(error.localizedDescription)"
        }
    }

    // MARK: Internals

    /// Adds clients that are not saved yet (new or example clients).
    func insert(_ client: Client) {
        clients.append(client)
        clients.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        unsavedIDs.insert(client.id)
        selectedID = client.id
    }

    private func load() {
        let result = folder.loadAll()
        clients = result.documents.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if !result.unreadable.isEmpty {
            statusMessage = "\(result.unreadable.count) client file(s) could not be read and were skipped."
        }
    }
}

extension ClientRegistryStore: UnsavedWorkProviding {
    var unsavedWorkKind: String { "Clients" }
    var unsavedItemNames: [String] { unsavedClients.map(\.displayName) }
    func saveAllUnsavedWork() -> Bool { saveAll() }
    var unsavedWorkStatus: String { statusMessage }
}
