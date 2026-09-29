import AppKit

/// Blacks out the desktop wallpaper on every screen, and puts the original back exactly.
///
/// On macOS 14+ WallpaperAgent keeps every screen's and Space's wallpaper — including dynamic
/// and aerial ones NSWorkspace cannot express — in one store file. Restoring a copy of that
/// file and restarting the agent brings all of it back. The per-screen NSWorkspace image URLs
/// are journalled too, as the fallback for a Mac without the store.
enum Wallpaper {
    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var store: URL {
        appSupport.appendingPathComponent("com.apple.wallpaper/Store/Index.plist")
    }

    private static var dir: URL {
        let d = appSupport.appendingPathComponent("ShowMode", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static var backup: URL { dir.appendingPathComponent("wallpaper-store.plist") }
    private static var blackImage: URL { dir.appendingPathComponent("black.png") }

    static var blackedOut: Bool { Journal.shared["wallpaper"] != nil }

    static func blackOut() {
        Journal.shared.load()
        if Journal.shared["wallpaper"] == nil {
            var j: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: store.path) {
                try? FileManager.default.removeItem(at: backup)
                if (try? FileManager.default.copyItem(at: store, to: backup)) != nil { j["store"] = backup.path }
            }
            var screens: [String: String] = [:]
            for s in NSScreen.screens {
                if let id = displayID(s), let url = NSWorkspace.shared.desktopImageURL(for: s) {
                    screens[String(id)] = url.path
                }
            }
            j["screens"] = screens
            Journal.shared["wallpaper"] = j
        }
        applyBlack()
    }

    /// Paints every current screen black. Called again when a screen is plugged in mid-show,
    /// so a projector connected after engage never shows the operator's wallpaper.
    static func applyBlack() {
        guard blackedOut, writeBlackImage() else { return }
        let opts: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
            .allowClipping: true,
            .fillColor: NSColor.black,
        ]
        for s in NSScreen.screens where NSWorkspace.shared.desktopImageURL(for: s) != blackImage {
            do { try NSWorkspace.shared.setDesktopImageURL(blackImage, for: s, options: opts) }
            catch { NSLog("ShowMode: could not black out \(s.localizedName): \(error)") }
        }
    }

    static func restore() {
        guard let j = Journal.shared["wallpaper"] as? [String: Any] else { return }
        if let path = j["store"] as? String, FileManager.default.fileExists(atPath: path) {
            // Replace the store, then restart the agent so it rereads it.
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            if let data, (try? data.write(to: store, options: .atomic)) != nil {
                Shell.killall("WallpaperAgent")
                try? FileManager.default.removeItem(atPath: path)
                return
            }
        }
        let screens = j["screens"] as? [String: String] ?? [:]
        for s in NSScreen.screens {
            guard let id = displayID(s), let path = screens[String(id)] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: s, options: [:])
        }
    }

    /// Restores just the wallpaper, leaving any other guard as it is.
    static func restoreOnly() {
        Journal.shared.load()
        restore()
        Journal.shared["wallpaper"] = nil
        if Journal.shared.entries.isEmpty { Journal.shared.clear() }
    }

    private static func writeBlackImage() -> Bool {
        if FileManager.default.fileExists(atPath: blackImage.path) { return true }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8,
                                   samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep, let bytes = rep.bitmapData else { return false }
        bytes.initialize(repeating: 0, count: rep.bytesPerRow * 16)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: blackImage, options: .atomic)) != nil
    }

    private static func displayID(_ s: NSScreen) -> CGDirectDisplayID? {
        (s.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
