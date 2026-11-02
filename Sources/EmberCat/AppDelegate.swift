import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = SpeedMonitorModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Retire the old opt-in so upgrading cannot restore the removed overlay.
        UserDefaults.standard.removeObject(forKey: "notchFlamesEnabled")
        statusItem = StatusItemController(viewModel: viewModel)
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem?.stop()
        viewModel.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { statusItem?.showMenu() }
        return false
    }
}
