import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("InkFlow: applicationDidFinishLaunching")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else {
            NSLog("InkFlow: status item has no button — menu bar may be full")
            return
        }

        if let image = NSImage(systemSymbolName: "scribble.variable",
                               accessibilityDescription: "InkFlow") {
            image.isTemplate = true
            button.image = image
        } else {
            NSLog("InkFlow: SF Symbol 'scribble.variable' unavailable — falling back to title")
            button.title = "Ink"
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit InkFlow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
    }
}
