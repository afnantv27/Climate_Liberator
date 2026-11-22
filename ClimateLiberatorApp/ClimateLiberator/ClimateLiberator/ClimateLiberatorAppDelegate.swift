import AppKit

/// App delegate hook for the quit prompt. Every store holding unsaved work
/// (inventories, engagements, clients, reduction plans) is asked about at once.
final class ClimateLiberatorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        UnsavedWorkGuard.terminationReply()
    }
}
