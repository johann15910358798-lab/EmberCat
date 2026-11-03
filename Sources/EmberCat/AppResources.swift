import AppKit

private final class ResourceBundleMarker {}

enum AppResources {
    @MainActor
    static let dockIdleCat: NSImage? = {
        guard let folder = directory("DockIdleCat"),
              let image = NSImage(contentsOf: folder.appendingPathComponent("CatIdle.png")),
              image.isValid else { return nil }
        image.isTemplate = false
        return image
    }()

    // Packaged apps have loose resources; SwiftPM builds use a sibling bundle.
    // Bundle.module traps when that bundle is absent, so probe optional bundles.
    private static let roots: [URL] = {
        let candidates = [Bundle.main.resourceURL,
                          Bundle(for: ResourceBundleMarker.self).resourceURL,
                          Bundle.main.bundleURL].compactMap { $0 }
        let packageBundles = candidates.compactMap {
            Bundle(url: $0.appendingPathComponent("EmberCat_EmberCat.bundle"))
        }
        return ([Bundle.main] + packageBundles).compactMap(\.resourceURL)
    }()

    static func directory(_ relativePath: String) -> URL? {
        roots.lazy.map { $0.appendingPathComponent(relativePath) }.first {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}
