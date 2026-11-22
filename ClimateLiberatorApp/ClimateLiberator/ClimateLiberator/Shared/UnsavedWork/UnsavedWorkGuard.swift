import AppKit

/// One quit prompt for every module: lists the unsaved items, then saves all,
/// discards, or cancels the quit. A failed save cancels the quit.
@MainActor
enum UnsavedWorkGuard {
    static func terminationReply() -> NSApplication.TerminateReply {
        terminationReply(providers: UnsavedWorkRegistry.providersWithUnsavedWork)
    }

    static func terminationReply(providers: [UnsavedWorkProviding]) -> NSApplication.TerminateReply {
        guard !providers.isEmpty else { return .terminateNow }
        let prompt = UnsavedWorkPrompt(groups: providers.map { (kind: $0.unsavedWorkKind, names: $0.unsavedItemNames) })

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.title
        alert.informativeText = prompt.detail
        alert.addButton(withTitle: prompt.saveButton)
        let dontSave = alert.addButton(withTitle: "Don’t Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let failed = providers.filter { !$0.saveAllUnsavedWork() }
            guard !failed.isEmpty else { return .terminateNow }
            let failure = NSAlert()
            failure.messageText = "Some changes could not be saved."
            failure.informativeText = failed.map { "\($0.unsavedWorkKind): \($0.unsavedWorkStatus)" }.joined(separator: "\n")
            failure.runModal()
            return .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
