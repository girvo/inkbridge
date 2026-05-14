import AppKit

final class PermissionsWindowController: NSWindowController, NSWindowDelegate {

    enum Kind {
        case accessibility
        case inputMonitoring
    }

    var onAllGranted: (() -> Void)?

    private let accessibilityRow: PermissionRow
    private let inputMonitoringRow: PermissionRow
    private var pollTimer: Timer?
    private var autoDismissWhenGranted: Bool = true
    private var lastAllGranted: Bool = false

    init() {
        accessibilityRow = PermissionRow(
            title: "Accessibility",
            subtitle: "Required to inject pointer events.",
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
            requestAction: { Permissions.requestAccessibility() }
        )
        inputMonitoringRow = PermissionRow(
            title: "Input Monitoring",
            subtitle: "Required to read the Supernote stylus.",
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!,
            requestAction: { Permissions.requestInputMonitoring() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "InkBridge Permissions"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating

        super.init(window: window)
        window.delegate = self

        let header = NSTextField(wrappingLabelWithString: "InkBridge needs two macOS permissions before it can drive the cursor:")
        header.font = .systemFont(ofSize: NSFont.systemFontSize)

        let footer = NSTextField(wrappingLabelWithString: "Status updates automatically. Once both rows are green, this window closes and InkBridge starts.")
        footer.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [header, accessibilityRow, inputMonitoringRow, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        window.contentView = content
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func present(autoDismissWhenGranted: Bool) {
        self.autoDismissWhenGranted = autoDismissWhenGranted
        lastAllGranted = false
        refresh()
        if window?.isVisible == true && autoDismissWhenGranted && Permissions.bothGranted() {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refresh() {
        let ax = Permissions.accessibilityGranted()
        let im = Permissions.inputMonitoringGranted()
        accessibilityRow.setGranted(ax)
        inputMonitoringRow.setGranted(im)
        let now = ax && im
        if now && !lastAllGranted {
            onAllGranted?()
            if autoDismissWhenGranted {
                stopPolling()
                window?.close()
            }
        }
        lastAllGranted = now
    }
}

private final class PermissionRow: NSStackView {

    private let statusIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton(title: "Open System Settings…", target: nil, action: nil)

    private let settingsURL: URL
    private let requestAction: () -> Void

    init(title: String, subtitle: String, settingsURL: URL, requestAction: @escaping () -> Void) {
        self.settingsURL = settingsURL
        self.requestAction = requestAction
        super.init(frame: .zero)

        titleLabel.stringValue = title
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        subtitleLabel.stringValue = subtitle
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 11)

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        statusIcon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            statusIcon.widthAnchor.constraint(equalToConstant: 22),
            statusIcon.heightAnchor.constraint(equalToConstant: 22),
        ])

        openButton.target = self
        openButton.action = #selector(handleOpen)
        openButton.bezelStyle = .rounded
        openButton.setContentHuggingPriority(.required, for: .horizontal)

        orientation = .horizontal
        alignment = .centerY
        spacing = 12
        let leftStack = NSStackView(views: [statusIcon, textStack])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 10
        leftStack.setHuggingPriority(.defaultLow, for: .horizontal)

        addArrangedSubview(leftStack)
        addArrangedSubview(openButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setGranted(_ granted: Bool) {
        if granted {
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                       accessibilityDescription: "Granted")
            statusIcon.contentTintColor = .systemGreen
            openButton.isHidden = true
        } else {
            statusIcon.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                       accessibilityDescription: "Not granted")
            statusIcon.contentTintColor = .systemRed
            openButton.isHidden = false
        }
    }

    @objc private func handleOpen() {
        requestAction()
        NSWorkspace.shared.open(settingsURL)
    }
}
