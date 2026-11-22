import Foundation

extension DisclosureStore: UnsavedWorkProviding {
    var unsavedWorkKind: String { "Disclosure engagements" }
    var unsavedItemNames: [String] { unsavedEngagements.map(\.displayName) }
    func saveAllUnsavedWork() -> Bool { saveAll() }
    var unsavedWorkStatus: String { statusMessage }
}
