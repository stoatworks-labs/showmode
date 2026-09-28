// Stoatworks Labs - About window for the AppKit apps.
//
// The same six things every other Stoatworks Labs product shows: the name, the
// version it is actually running, its user guide, its project page, its source,
// and the four ways to fund the work - over the Stoatworks Labs mark.
//
// This file is the MASTER, in stoatworks-backend/about/swift. It is vendored
// into each AppKit repo by ../../scripts/sync-about.py - edit it THERE and re-run
// the sync, never the copies. The facts come from `StoatworksAboutData.swift`
// beside it, which is generated from the website's projects.json, and the mark
// from `StoatworksAboutMark.swift`.
//
// Using it, from a menu item:
//
//     StoatworksAbout.show()
//
// The version is CFBundleShortVersionString - what the bundle actually is.
// `StoatworksAboutData.versionFallback` is only for a bare executable run
// outside its .app, which has no Info.plist to ask.

import AppKit

enum StoatworksAbout {
    private static var window: NSWindow?

    static var runningVersion: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !v.isEmpty {
            return v.hasPrefix("v") ? v : "v" + v
        }
        return StoatworksAboutData.versionFallback
    }

    static func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // The navy card every other surface uses, whatever the app's own appearance:
    // it is brand furniture rather than part of the app's UI.
    private static let navy = NSColor(srgbRed: 0x0f / 255, green: 0x1b / 255, blue: 0x2d / 255, alpha: 1)
    private static let cyan = NSColor(srgbRed: 0x4c / 255, green: 0xc9 / 255, blue: 0xf0 / 255, alpha: 1)
    private static let text = NSColor(white: 0.94, alpha: 1)
    private static let weak = NSColor(white: 0.94, alpha: 0.6)

    private static func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 10),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "About \(StoatworksAboutData.name)"
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = navy

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        stack.addArrangedSubview(label(StoatworksAboutData.name, size: 20, weight: .semibold, color: text))
        var line = runningVersion
        if !StoatworksAboutData.licence.isEmpty { line += "   \(StoatworksAboutData.licence) licensed" }
        let version = label(line, size: 12, color: weak, mono: true)
        let attr = NSMutableAttributedString(attributedString: version.attributedStringValue)
        attr.addAttribute(.foregroundColor, value: cyan, range: NSRange(location: 0, length: (runningVersion as NSString).length))
        version.attributedStringValue = attr
        stack.addArrangedSubview(version)

        if !StoatworksAboutData.hook.isEmpty {
            stack.setCustomSpacing(10, after: version)
            stack.addArrangedSubview(label(StoatworksAboutData.hook, size: 13, color: weak))
        }

        // A link is shown only if this product actually has one: a guide that
        // has not been written, or a repo that is still private, is an empty
        // string here and is left out rather than pointed at a URL that 404s.
        let rows = [("User guide", StoatworksAboutData.guide),
                    ("Project page", StoatworksAboutData.page),
                    ("Source on GitHub", StoatworksAboutData.repo)].filter { !$0.1.isEmpty }
        if !rows.isEmpty {
            addHeading("DOCUMENTATION", to: stack)
            rows.forEach { stack.addArrangedSubview(link($0.0, $0.1)) }
        }

        addHeading("SUPPORT THE WORK", to: stack)
        let funding = NSStackView(views: StoatworksAboutData.funding.map { link($0.0, $0.1) })
        funding.spacing = 14
        stack.addArrangedSubview(funding)

        let rule = NSBox()
        rule.boxType = .separator
        stack.addArrangedSubview(rule)
        stack.setCustomSpacing(12, after: funding)
        rule.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        stack.addArrangedSubview(label("\(StoatworksAboutData.org) - \(StoatworksAboutData.tagline)", size: 11, color: weak))
        stack.addArrangedSubview(link(StoatworksAboutData.home, StoatworksAboutData.home))

        let root = NSView()
        if let data = Data(base64Encoded: StoatworksAboutMark.pngBase64), let img = NSImage(data: data) {
            let mark = NSImageView(image: img)
            mark.imageScaling = .scaleProportionallyUpOrDown
            mark.alphaValue = 0.07
            mark.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(mark)
            NSLayoutConstraint.activate([
                mark.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                mark.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                mark.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.78),
            ])
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: 400),
        ])
        w.contentView = root
        return w
    }

    private static func label(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular,
                              color: NSColor, mono: Bool = false) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.preferredMaxLayoutWidth = 352
        return l
    }

    private static func addHeading(_ s: String, to stack: NSStackView) {
        if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(14, after: last) }
        stack.addArrangedSubview(label(s, size: 10, weight: .medium, color: weak))
    }

    private static func link(_ title: String, _ url: String) -> NSButton {
        let b = LinkButton(title: title, target: nil, action: nil)
        b.url = URL(string: url)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: cyan, .font: NSFont.systemFont(ofSize: 13),
        ])
        b.target = b
        b.action = #selector(LinkButton.open)
        return b
    }

    private final class LinkButton: NSButton {
        var url: URL?
        @objc func open() { if let url { NSWorkspace.shared.open(url) } }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
