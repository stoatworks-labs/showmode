import AppKit

/// Finds and moves PowerPoint's slide show window, so the screen layout lock can put a cloned
/// screen back without leaving the slides on it.
///
/// What PowerPoint for Mac does to the screens (16.112.3 on macOS 26.4.1, benched with virtual
/// displays): with Presenter View on it splits every mirror when the show starts, puts Presenter
/// View on the main display and the slides on one of the screens that came out — the old clone,
/// not the extended projector, on the bench — and puts the mirrors back when the show ends. With
/// Presenter View off and the screens extended it mirrors them all instead. It does not fight a
/// change made mid-show, but it does not follow one either: a split mirror leaves the slides
/// where they were, and a remade one strands them behind Presenter View.
///
/// Through osascript, not NSAppleScript: an Apple Event to a busy PowerPoint can wait for
/// minutes, and this way a timeout kills it. Call off the main thread. Setting `bounds` is a
/// silent no-op; the four edges each work, but setting one to the value it already has fails
/// (-10006), hence one `try` each.
enum PowerPoint {
    static let bundleID = "com.microsoft.Powerpoint"

    static var running: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    enum Answer {
        /// The slide show windows, in global CG coordinates (origin top-left of the main display).
        case shows([CGRect])
        /// macOS has not let Show Mode control PowerPoint (Automation).
        case notAllowed
        /// No answer in time, or not running.
        case none

        var notAllowed: Bool {
            if case .notAllowed = self { return true }
            return false
        }
    }

    /// `timeout` is longer when someone is there to answer macOS's question whether Show Mode may
    /// control PowerPoint: osascript waits on it.
    static func slideShows(timeout: TimeInterval = 5) -> Answer {
        // Not `out`: PowerPoint's dictionary has the word, and `set out to {}` fails (-10003).
        parse(osascript(timeout: timeout, """
            tell application id "\(bundleID)"
              set theFrames to {}
              repeat with i from 1 to count of slide show windows
                set end of theFrames to \(frame("slide show window i"))
              end repeat
              set AppleScript's text item delimiters to linefeed
              return theFrames as text
            end tell
            """))
    }

    /// Moves slide show window `index` (1-based) onto `rect`; true if it reads back there.
    static func move(_ index: Int, to rect: CGRect) -> Bool {
        let r = rect.integral
        let answer = parse(osascript("""
            tell application id "\(bundleID)"
              tell slide show window \(index)
                try
                  set left position to \(Int(r.minX))
                end try
                try
                  set top to \(Int(r.minY))
                end try
                try
                  set width to \(Int(r.width))
                end try
                try
                  set height to \(Int(r.height))
                end try
              end tell
              return \(frame("slide show window \(index)"))
            end tell
            """))
        if case .shows(let frames) = answer, frames.first == r { return true }
        return false
    }

    /// AppleScript for "left top width height" of a window, whole numbers so no locale decimal
    /// separator gets in.
    private static func frame(_ w: String) -> String {
        ["left position", "top", "width", "height"]
            .map { "((\($0) of \(w)) as integer as text)" }
            .joined(separator: " & \" \" & ")
    }

    /// Runs `source` only if PowerPoint is running: asking it anything would launch it. The
    /// check is in the script, not `running`, which is unreliable off the main thread.
    private static func osascript(timeout: TimeInterval = 5, _ source: String) -> (status: Int32, out: String)? {
        let guarded = """
            if application id "\(bundleID)" is running then
            \(source)
            end if
            return "\(notRunning)"
            """
        return Shell.run("/usr/bin/osascript", ["-e", guarded], timeout: timeout)
    }

    private static let notRunning = "not running"

    private static func parse(_ result: (status: Int32, out: String)?) -> Answer {
        guard let result, result.out.trimmingCharacters(in: .whitespacesAndNewlines) != notRunning else { return .none }
        guard result.status == 0 else {
            // errAEEventNotPermitted: the Automation switch is off, or the prompt was refused.
            return result.out.contains("-1743") ? .notAllowed : .none
        }
        let frames = result.out.split(whereSeparator: \.isNewline).compactMap { line -> CGRect? in
            let n = line.split(separator: " ").compactMap { Int($0) }
            guard n.count == 4 else { return nil }
            return CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
        }
        return .shows(frames)
    }
}

/// Windows of other apps that exactly cover a display: a slide show, a full-screen player.
/// Owner names need no Screen Recording permission (window titles would).
enum FullScreen {
    static func owners(on bounds: CGRect) -> [(pid: pid_t, name: String)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = getpid()
        return list.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b), rect.integral == bounds.integral
            else { return nil }
            return (pid, w[kCGWindowOwnerName as String] as? String ?? "an app")
        }
    }
}
