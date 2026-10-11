import AppKit

/// Restarts, shut-downs and log-outs during a show. Before any of them macOS asks every app to
/// quit, with the reason attached, and one app refusing stops the whole thing. Show Mode refuses
/// while a show runs, so an update's overnight restart, or a stray Restart…, waits for the show
/// to end. The other apps were asked at the same moment and some will already have quit: those
/// are opened again. A forced restart (`shutdown -r`, an organisation's deadline) asks no one,
/// and nothing stops it.
enum Restarts {
    enum Kind: String {
        case restart, shutDown = "shut-down", logOut = "log-out"

        var verb: String {
            switch self {
            case .restart: return "restart"
            case .shutDown: return "shut down"
            case .logOut: return "log out"
            }
        }
    }

    /// Which of the three the quit Apple Event being handled is for; nil for an ordinary Quit
    /// (the menu, ⌘Q, a script), which carries no reason.
    static var reason: Kind? {
        guard let e = NSAppleEventManager.shared().currentAppleEvent,
              e.eventClass == AEEventClass(kCoreEventClass), e.eventID == AEEventID(kAEQuitApplication),
              let why = (e.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
                         ?? e.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)))?.typeCodeValue
        else { return nil }
        switch why {
        case OSType(kAERestart), OSType(kAEShowRestartDialog): return .restart
        case OSType(kAEShutDown), OSType(kAEShowShutdownDialog): return .shutDown
        case OSType(kAELogOut), OSType(kAEReallyLogOut): return .logOut
        default: return nil
        }
    }
}

/// The apps that quit during a show, and the last one in front, so the ones a refused restart
/// took with it can be opened again.
final class AppQuits {
    private var observers: [NSObjectProtocol] = []
    private var quits: [(url: URL, at: Date)] = []
    private(set) var front: URL?

    func start() {
        guard observers.isEmpty else { return }
        quits = []
        front = NSWorkspace.shared.frontmostApplication.flatMap(Self.regular)
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let url = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).flatMap(Self.regular)
            else { return }
            self.quits = self.quits.filter { Date().timeIntervalSince($0.at) < 120 } + [(url, Date())]
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let url = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication).flatMap(Self.regular) {
                self?.front = url
            }
        })
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        quits = []
    }

    /// Apps that quit since `date` and are not running again.
    func quit(since date: Date) -> [URL] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleURL))
        var seen = Set<URL>()
        return quits.filter { $0.at >= date && !running.contains($0.url) && seen.insert($0.url).inserted }.map(\.url)
    }

    /// Ordinary apps with a window and a Dock icon; never Show Mode itself.
    private static func regular(_ app: NSRunningApplication) -> URL? {
        app.activationPolicy == .regular && app.processIdentifier != getpid() ? app.bundleURL : nil
    }
}
