import AppKit

if CommandLine.arguments.contains("--check-assets") {
    exit(checkMenuBarResources() ? 0 : 1)
}

if let index = CommandLine.arguments.firstIndex(of: "--export-pixelfx-suite") {
    guard CommandLine.arguments.count > index + 1 else {
        fputs("Usage: EmberCat --export-pixelfx-suite OUTPUT_DIRECTORY\n", stderr)
        exit(1)
    }
    do {
        try exportSuitePreview(to: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true))
        exit(0)
    } catch {
        fputs("Suite export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--export-motion-preview") {
    guard CommandLine.arguments.count > index + 1 else {
        fputs("Usage: EmberCat --export-motion-preview OUTPUT_DIRECTORY\n", stderr)
        exit(1)
    }
    do {
        try exportMotionPreview(to: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true))
        exit(0)
    } catch {
        fputs("Preview export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--export-cat-preview") {
    guard CommandLine.arguments.count > index + 1 else {
        fputs("Usage: EmberCat --export-cat-preview OUTPUT_DIRECTORY\n", stderr)
        exit(1)
    }
    do {
        try exportCatPreview(to: URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true))
        exit(0)
    } catch {
        fputs("Cat preview export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--export-flame-preview") {
    guard CommandLine.arguments.count > index + 1 else {
        fputs("Usage: EmberCat --export-flame-preview OUTPUT_DIRECTORY\n", stderr)
        exit(1)
    }
    do {
        try exportFlamePreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        exit(0)
    } catch {
        fputs("Flame export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--preview-flame")
    || Bundle.main.object(forInfoDictionaryKey: "EmberCatFlamePreview") as? Bool == true {
    let delegate = FlamePreviewAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
} else if CommandLine.arguments.contains("--preview-motion") || CommandLine.arguments.contains("--preview-pixelfx-walk")
    || CommandLine.arguments.contains("--preview-pixelfx-vehicles")
    || CommandLine.arguments.contains("--preview-pixelfx-suite")
    || Bundle.main.object(forInfoDictionaryKey: "EmberCatMotionPreview") as? Bool == true
    || Bundle.main.object(forInfoDictionaryKey: "EmberCatPixelFXWalkPreview") as? Bool == true
    || Bundle.main.object(forInfoDictionaryKey: "EmberCatPixelFXVehiclePreview") as? Bool == true
    || Bundle.main.object(forInfoDictionaryKey: "EmberCatPixelFXSuitePreview") as? Bool == true {
    let delegate = PreviewAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
