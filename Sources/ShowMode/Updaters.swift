import AppKit

/// Apps' own update checks, whose "a new version is available" windows open on whatever
/// screen they like and are not notifications, so Do Not Disturb does not hold them.
enum AppUpdaters {
    /// Running apps that update through Sparkle (most apps from outside the App Store).
    /// Sparkle reads SUEnableAutomaticChecks from the app's own defaults before its Info.plist,
    /// and Sparkle 2 watches the key while it runs, so writing it takes effect without a
    /// relaunch. A sandboxed app keeps its defaults in its container, out of reach: skipped.
    static func sparkleApps() -> [(id: String, name: String)] {
        let containers = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers")
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, let url = app.bundleURL, !seen.contains(id),
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Sparkle.framework").path),
                  !FileManager.default.fileExists(atPath: containers.appendingPathComponent(id).path)
            else { return nil }
            seen.insert(id)
            return (id, app.localizedName ?? id)
        }
    }

    /// Microsoft AutoUpdate, for Office and Teams. "Manual" is deprecated but still honoured.
    static let mau = PrefKey(domain: "com.microsoft.autoupdate2", key: "HowToCheck")
    static var mauInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app")
    }
    /// Set by the organisation; its update deadlines force-quit apps whatever this says.
    static var mauManaged: Bool { CFPreferencesAppValueIsForced(mau.key as CFString, mau.domain as CFString) }

    /// Returns the names of the apps whose checks were turned off.
    @discardableResult
    static func engage() -> [String] {
        var names: [String] = []
        for app in sparkleApps() {
            let k = PrefKey(domain: app.id, key: "SUEnableAutomaticChecks")
            if (k.read() as? Bool) != false, k.override(false) { names.append(app.name) }
        }
        if mauInstalled, !mauManaged, (mau.read() as? String) != "Manual", mau.override("Manual") {
            names.append("Microsoft AutoUpdate")
        }
        if !names.isEmpty { ShowLog.note("update checks off: \(names.joined(separator: ", "))") }
        return names
    }
}

/// Apps quit for the show by bundle identifier and opened again afterwards, in the background.
enum QuitApps {
    /// Journals each app's location before quitting it.
    static func quit(_ ids: [String]) {
        var quit = Journal.shared["quitApps"] as? [String] ?? []
        for id in ids {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                if let path = app.bundleURL?.path, !quit.contains(path) {
                    quit.append(path)
                    Journal.shared["quitApps"] = quit
                }
                app.terminate()
            }
        }
    }

    static func relaunch() {
        for path in Journal.shared["quitApps"] as? [String] ?? [] {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
        }
    }
}

/// Syncthing, through its own local REST API: every folder that is syncing is paused for the
/// show (which stops its scanning as well as its transfers, LAN included), and only those are
/// resumed afterwards. A folder already paused stays paused.
enum Syncthing {
    struct API {
        let base: URL
        let key: String
    }

    /// The GUI address and API key from Syncthing's config; nil if it is not set up here or
    /// listens on a socket.
    static func api() -> API? {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Syncthing/config.xml")
        guard let doc = try? XMLDocument(contentsOf: config),
              let gui = try? doc.nodes(forXPath: "/configuration/gui").first as? XMLElement,
              let address = gui.elements(forName: "address").first?.stringValue,
              let key = gui.elements(forName: "apikey").first?.stringValue, !key.isEmpty,
              let port = address.split(separator: ":").last.flatMap({ Int($0) })
        else { return nil }
        let tls = gui.attribute(forName: "tls")?.stringValue == "true"
        // Always the loopback address: the GUI may listen on every interface.
        guard let base = URL(string: "\(tls ? "https" : "http")://127.0.0.1:\(port)") else { return nil }
        return API(base: base, key: key)
    }

    /// One request with a short timeout. nil if Syncthing did not answer.
    private static func call(_ api: API, _ method: String, _ path: String, _ body: [String: Any]? = nil) -> (Int, Data)? {
        guard let url = URL(string: path, relativeTo: api.base) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = method
        req.setValue(api.key, forHTTPHeaderField: "X-API-Key")
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var result: (Int, Data)?
        let done = DispatchSemaphore(value: 0)
        LoopbackSession.shared.dataTask(with: req) { data, response, _ in
            if let code = (response as? HTTPURLResponse)?.statusCode { result = (code, data ?? Data()) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 4)
        return result
    }

    private static func folderPath(_ id: String) -> String {
        "rest/config/folders/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id)
    }

    /// Pauses the syncing folders. Returns false if Syncthing answered but would not pause
    /// one; true when it is paused or not running at all.
    static func engage() -> Bool {
        guard let api = api(), let (code, data) = call(api, "GET", "rest/config/folders"), code == 200,
              let folders = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return true }
        let syncing = folders.compactMap { f -> String? in
            guard let id = f["id"] as? String, (f["paused"] as? Bool) != true else { return nil }
            return id
        }
        guard !syncing.isEmpty else { return true }
        var journaled = Journal.shared["syncthingFolders"] as? [String] ?? []
        journaled += syncing.filter { !journaled.contains($0) }
        Journal.shared["syncthingFolders"] = journaled
        var ok = true
        for id in syncing where call(api, "PATCH", folderPath(id), ["paused": true])?.0 != 200 { ok = false }
        ShowLog.note("Syncthing: paused \(syncing.count) folder(s)\(ok ? "" : ", not all")")
        return ok
    }

    /// Returns false if a folder could not be resumed — Syncthing not answering yet at login,
    /// say. Syncthing saves the paused state, so those stay journaled and are retried. With no
    /// Syncthing config any more there is nothing to resume.
    static func restore() -> Bool {
        guard let ids = Journal.shared["syncthingFolders"] as? [String], let api = api() else { return true }
        let left = ids.filter { call(api, "PATCH", folderPath($0), ["paused": false])?.0 != 200 }
        Journal.shared["syncthingFolders"] = left.isEmpty ? nil : left
        return left.isEmpty
    }
}

/// A URLSession that accepts the self-signed certificate Syncthing's GUI uses, for the
/// loopback address only.
private final class LoopbackSession: NSObject, URLSessionDelegate {
    static let shared: URLSession = URLSession(configuration: .ephemeral, delegate: LoopbackSession(), delegateQueue: nil)

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
