import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = SpeedMonitorModel()
    private var statusItem: StatusItemController?
    private var flame: NotchFlameController?
    private var dockCat: DockOrbitController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        flame = NotchFlameController()
        dockCat = DockOrbitController()
        viewModel.onSnapshotChange = { [weak self] snapshot in
            self?.flame?.update(speed: snapshot.live.output)
            self?.dockCat?.update(speed: snapshot.live.output)
        }
        statusItem = StatusItemController(viewModel: viewModel)
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem?.stop()
        viewModel.onSnapshotChange = nil
        flame?.shutdown()
        dockCat?.shutdown()
        viewModel.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Decorative surfaces must not suppress the menu's reopen entry.
        let hasInteractiveWindow = sender.windows.contains { $0.isVisible && $0.canBecomeKey }
        if !hasInteractiveWindow { statusItem?.showMenu() }
        return false
    }
}
