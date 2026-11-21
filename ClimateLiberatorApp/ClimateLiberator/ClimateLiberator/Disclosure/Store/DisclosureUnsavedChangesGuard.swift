import AppKit

/// Asks before quitting when client engagements have unsaved changes, so nothing is
/// written (or lost) without the user deciding.
@MainActor
enum DisclosureUnsavedChangesGuard {
    static func terminationReply() -> NSApplication.TerminateReply {
        guard let store = DisclosureStore.active, store.hasUnsavedChanges else { return .terminateNow }
        let names = store.unsavedEngagements.map(\.displayName)

        let alert = NSAlert()
        alert.alertStyle = .warning
        if names.count == 1 {
            alert.messageText = "Do you want to save the disclosure engagement “\(names[0])”?"
            alert.informativeText = "Your changes will be lost if you don’t save them."
        } else {
            alert.messageText = "Do you want to save \(names.count) disclosure engagements?"
            alert.informativeText = names.map { "• \($0)" }.joined(separator: "\n")
                + "\n\nYour changes will be lost if you don’t save them."
        }
        alert.addButton(withTitle: names.count == 1 ? "Save" : "Save All")
        let dontSave = alert.addButton(withTitle: "Don’t Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if store.saveAll() { return .terminateNow }
            let failure = NSAlert()
            failure.messageText = "Some engagements could not be saved."
            failure.informativeText = store.statusMessage
            failure.runModal()
            return .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
