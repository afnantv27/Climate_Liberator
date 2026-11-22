import Foundation

extension GPCInventoryStore: UnsavedWorkProviding {
    var unsavedWorkKind: String { "GHG inventories" }
    var unsavedItemNames: [String] { unsavedInventories.map(\.displayName) }
    func saveAllUnsavedWork() -> Bool { saveAll() }
    var unsavedWorkStatus: String { statusMessage }
}
