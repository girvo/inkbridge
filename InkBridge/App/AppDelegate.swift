import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences()
    private let controller = InkFlowController()
    private var statusItemController: StatusItemController!
    private var permissionsWindow: PermissionsWindowController?
    private var controllerStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("InkBridge: applicationDidFinishLaunching")

        statusItemController = StatusItemController()
        statusItemController.apply(controller.state)
        statusItemController.setExcalidrawChecked(prefs.excalidrawMode)
        statusItemController.onToggleExcalidraw = { [weak self] in
            self?.toggleExcalidraw()
        }
        statusItemController.onOpenPermissions = { [weak self] in
            self?.showPermissionsWindow(autoDismissWhenGranted: false)
        }
        statusItemController.setLaunchAtLoginChecked(LaunchAtLogin.isEnabled)
        statusItemController.onToggleLaunchAtLogin = { [weak self] in
            self?.toggleLaunchAtLogin()
        }
        statusItemController.onOpenAbout = { [weak self] in
            self?.showAboutPanel()
        }
        statusItemController.setCurrentDisplay(prefs.targetDisplayID)
        statusItemController.onSelectDisplay = { [weak self] id in
            self?.selectDisplay(id)
        }
        controller.targetDisplayID = prefs.targetDisplayID

        controller.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.statusItemController.apply(state)
            }
        }
        controller.excalidrawMode = prefs.excalidrawMode

        if Permissions.bothGranted() {
            startController()
        } else {
            showPermissionsWindow(autoDismissWhenGranted: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func startController() {
        guard !controllerStarted else { return }
        controllerStarted = true
        controller.start()
    }

    private func showPermissionsWindow(autoDismissWhenGranted: Bool) {
        if permissionsWindow == nil {
            let window = PermissionsWindowController()
            window.onAllGranted = { [weak self] in
                self?.startController()
            }
            permissionsWindow = window
        }
        permissionsWindow?.present(autoDismissWhenGranted: autoDismissWhenGranted)
    }

    private func toggleExcalidraw() {
        prefs.excalidrawMode.toggle()
        statusItemController.setExcalidrawChecked(prefs.excalidrawMode)
        controller.excalidrawMode = prefs.excalidrawMode
    }

    private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
        } catch {
            NSLog("InkBridge: launch-at-login toggle failed — \(error.localizedDescription)")
        }
        statusItemController.setLaunchAtLoginChecked(LaunchAtLogin.isEnabled)
        NSLog("InkBridge: launch-at-login is \(LaunchAtLogin.statusDescription)")
    }

    private func selectDisplay(_ id: CGDirectDisplayID?) {
        prefs.targetDisplayID = id
        controller.targetDisplayID = id
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Unofficial macOS support for the Supernote InkFlow feature — turns the Supernote into a graphics tablet without needing the Partner app.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
