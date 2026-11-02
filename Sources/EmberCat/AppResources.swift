import Foundation

private final class ResourceBundleMarker {}

enum AppResources {
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
