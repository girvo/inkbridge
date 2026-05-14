import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let statusMenuItem: NSMenuItem
    private let excalidrawMenuItem: NSMenuItem
    private let displayMenuItem: NSMenuItem
    private let displaySubmenu: NSMenu
    private let permissionsMenuItem: NSMenuItem
    private let launchAtLoginMenuItem: NSMenuItem
    private let aboutMenuItem: NSMenuItem

    private var currentDisplayID: CGDirectDisplayID?

    var onToggleExcalidraw: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    var onSelectDisplay: ((CGDirectDisplayID?) -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenuItem = NSMenuItem(title: "Waiting for device…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        excalidrawMenuItem = NSMenuItem(title: "Excalidraw eraser mode",
                                        action: nil,
                                        keyEquivalent: "")
        permissionsMenuItem = NSMenuItem(title: "Permissions…",
                                         action: nil,
                                         keyEquivalent: "")
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at login",
                                           action: nil,
                                           keyEquivalent: "")
        aboutMenuItem = NSMenuItem(title: "About InkBridge",
                                   action: nil,
                                   keyEquivalent: "")
        displayMenuItem = NSMenuItem(title: "Map to display", action: nil, keyEquivalent: "")
        displaySubmenu = NSMenu(title: "Map to display")

        super.init()

        excalidrawMenuItem.target = self
        excalidrawMenuItem.action = #selector(handleToggleExcalidraw)
        permissionsMenuItem.target = self
        permissionsMenuItem.action = #selector(handleOpenPermissions)
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.action = #selector(handleToggleLaunchAtLogin)
        aboutMenuItem.target = self
        aboutMenuItem.action = #selector(handleOpenAbout)
        displaySubmenu.delegate = self
        displayMenuItem.submenu = displaySubmenu

        if let button = statusItem.button {
            button.image = Self.menuBarImage(connected: false)
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(excalidrawMenuItem)
        menu.addItem(.separator())
        menu.addItem(displayMenuItem)
        menu.addItem(permissionsMenuItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(aboutMenuItem)
        menu.addItem(
            withTitle: "Quit InkBridge",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }

    func apply(_ state: InkFlowController.ConnectionState) {
        switch state {
        case .disconnected:
            statusMenuItem.attributedTitle = nil
            statusMenuItem.title = "Waiting for device…"
            statusItem.button?.image = Self.menuBarImage(connected: false)
            statusItem.button?.image?.isTemplate = true
        case .connected(let name, let serial):
            statusMenuItem.attributedTitle = Self.connectedTitle(name: name, serial: serial)
            statusItem.button?.image = Self.menuBarImage(connected: true)
            statusItem.button?.image?.isTemplate = true
        }
    }

    private static func connectedTitle(name: String, serial: String?) -> NSAttributedString {
        let title = NSMutableAttributedString()
        title.append(NSAttributedString(
            string: "Connected: \(name)",
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        ))
        if let serial = serial, !serial.isEmpty {
            title.append(NSAttributedString(
                string: "\n\(serial)",
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
        }
        return title
    }

    func setExcalidrawChecked(_ enabled: Bool) {
        excalidrawMenuItem.state = enabled ? .on : .off
    }

    func setLaunchAtLoginChecked(_ enabled: Bool) {
        launchAtLoginMenuItem.state = enabled ? .on : .off
    }

    func setCurrentDisplay(_ id: CGDirectDisplayID?) {
        currentDisplayID = id
    }

    @objc private func handleToggleExcalidraw() {
        onToggleExcalidraw?()
    }

    @objc private func handleOpenPermissions() {
        onOpenPermissions?()
    }

    @objc private func handleToggleLaunchAtLogin() {
        onToggleLaunchAtLogin?()
    }

    @objc private func handleOpenAbout() {
        onOpenAbout?()
    }

    @objc private func handleSelectDisplay(_ sender: NSMenuItem) {
        let id = (sender.representedObject as? NSNumber)?.uint32Value
        currentDisplayID = id
        onSelectDisplay?(id)
    }

    private func rebuildDisplaySubmenu() {
        displaySubmenu.removeAllItems()
        let screens = NSScreen.screens
        let mainID = NSScreen.main?.displayID
        let effectiveID = currentDisplayID ?? mainID

        for (index, screen) in screens.enumerated() {
            let id = screen.displayID
            let name = screen.localizedName.isEmpty
                ? "Display \(index + 1)"
                : screen.localizedName
            let isMain = (id == mainID)
            let title = isMain ? "\(name) (main)" : name
            let item = NSMenuItem(title: title,
                                  action: #selector(handleSelectDisplay(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = id.map { NSNumber(value: $0) }
            item.state = (id == effectiveID) ? .on : .off
            displaySubmenu.addItem(item)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === displaySubmenu {
            rebuildDisplaySubmenu()
        }
    }

    private static func menuBarImage(connected: Bool) -> NSImage? {
        let symbol = connected ? "scribble.variable" : "scribble"
        if let image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: connected ? "InkBridge connected" : "InkBridge waiting") {
            return image
        }
        return NSImage(systemSymbolName: "scribble.variable", accessibilityDescription: "InkBridge")
    }
}
