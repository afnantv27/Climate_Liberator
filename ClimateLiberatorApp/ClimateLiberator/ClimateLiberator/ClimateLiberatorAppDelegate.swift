import AppKit

/// App delegate hook for the quit prompts: GHG inventories first, then disclosure
/// engagements. Either prompt can cancel the quit.
final class ClimateLiberatorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let ghg = GHGUnsavedChangesGuard.terminationReply()
        guard ghg == .terminateNow else { return ghg }
        return DisclosureUnsavedChangesGuard.terminationReply()
    }
}
