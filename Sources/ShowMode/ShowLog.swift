import Foundation

/// A plain activity log at ~/Library/Logs/ShowMode.log, so an operator can see what show mode
/// did to the machine and when (Console.app opens it). Unified logging drops NSLog lines from
/// a background app too readily to be the record.
enum ShowLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ShowMode.log")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func note(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
