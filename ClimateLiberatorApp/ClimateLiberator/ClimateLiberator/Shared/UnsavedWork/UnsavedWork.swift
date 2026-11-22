import Foundation

/// A store that keeps edits in memory until the user saves. Nothing is written
/// without the user asking; before quitting, the app asks about every registered
/// store that still holds unsaved work.
@MainActor
protocol UnsavedWorkProviding: AnyObject {
    /// Plural noun shown in the quit prompt, e.g. "Clients".
    var unsavedWorkKind: String { get }
    /// Display names of the items with unsaved changes; empty when all is saved.
    var unsavedItemNames: [String] { get }
    /// Saves every unsaved item. Returns false if any could not be written.
    func saveAllUnsavedWork() -> Bool
    /// Explanation of the last failure, shown if saving at quit fails.
    var unsavedWorkStatus: String { get }
}

/// Weak list of stores that can hold unsaved work. Stores register themselves when
/// they are created for real use (not in tests that skip disk loading).
@MainActor
enum UnsavedWorkRegistry {
    private final class Entry {
        weak var provider: UnsavedWorkProviding?
        init(_ provider: UnsavedWorkProviding) { self.provider = provider }
    }

    private static var entries: [Entry] = []

    static func register(_ provider: UnsavedWorkProviding) {
        entries.removeAll { $0.provider == nil || $0.provider === provider }
        entries.append(Entry(provider))
    }

    static var providersWithUnsavedWork: [UnsavedWorkProviding] {
        entries.compactMap(\.provider).filter { !$0.unsavedItemNames.isEmpty }
    }
}

/// Text of the quit prompt, kept apart from AppKit so it can be tested.
nonisolated struct UnsavedWorkPrompt: Equatable, Sendable {
    let title: String
    let detail: String
    let saveButton: String

    /// `groups` pairs a kind ("Clients") with the unsaved item names in it.
    init(groups: [(kind: String, names: [String])]) {
        let nonEmpty = groups.filter { !$0.names.isEmpty }
        let total = nonEmpty.reduce(0) { $0 + $1.names.count }
        let lost = "Your changes will be lost if you don’t save them."
        if total == 1, let only = nonEmpty.first?.names.first {
            title = "Do you want to save “\(only)”?"
            detail = lost
            saveButton = "Save"
        } else {
            title = "Do you want to save your changes?"
            let lines = nonEmpty.map { group in
                "\(group.kind): " + group.names.joined(separator: ", ")
            }
            detail = lines.joined(separator: "\n") + "\n\n" + lost
            saveButton = "Save All"
        }
    }
}
