import AppKit

@MainActor
private final class MatrixDraftAppDelegate: NSObject, NSApplicationDelegate {
    private var preview: NotchFlamePreviewController?
    private let configuration: NotchMatrixConfiguration?

    init(configuration: NotchMatrixConfiguration?) { self.configuration = configuration }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            // A separate domain preserves this draft across launches without touching installed-app preferences.
            let defaults = UserDefaults(suiteName: "EmberCat.MatrixInteractiveDraft")!
            let settings = NotchFlameSettings(defaults: defaults)
            preview = try NotchFlamePreviewController(settings: settings,
                effect: .matrix, isIsolatedDraft: true)
            preview?.showWindow(nil)
            if let configuration { preview?.setMatrixDraftConfiguration(configuration) }
        } catch {
            fputs("Could not open the isolated Matrix draft: \(error.localizedDescription)\n", stderr)
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MatrixDraftExport {
    @MainActor static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 || arguments.count == 6 else {
            fputs("Usage: MatrixDraftExport OUTPUT_DIRECTORY|--interactive [--configuration SIZE GRAVITY DENSITY OFFSET_PT]\n", stderr)
            exit(1)
        }
        var configuration: NotchMatrixConfiguration?
        if arguments.count == 6 {
            guard arguments[1] == "--configuration", let size = Double(arguments[2]),
                  let gravity = Double(arguments[3]), let density = Double(arguments[4]),
                  let offset = Double(arguments[5]) else {
                fputs("Expected --configuration SIZE GRAVITY DENSITY OFFSET_PT\n", stderr)
                exit(1)
            }
            let requested = NotchMatrixConfiguration(blackHoleSize:size,gravity:gravity,
                density:density,verticalOffset:offset)
            if let error = requested.validationError {
                fputs("Invalid preview configuration: \(error)\n", stderr)
                exit(1)
            }
            configuration = requested
        }
        _ = NSApplication.shared
        if arguments[0] == "--interactive" {
            NSApp.setActivationPolicy(.regular)
            let delegate = MatrixDraftAppDelegate(configuration:configuration)
            NSApp.delegate = delegate
            withExtendedLifetime(delegate) { NSApp.run() }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        try exportMatrixPreview(to: URL(fileURLWithPath: arguments[0], isDirectory: true),
            configuration:configuration ?? .standard)
    }
}
