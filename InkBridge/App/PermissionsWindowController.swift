import AppKit

final class PermissionsWindowController: NSWindowController, NSWindowDelegate {

    var onAllGranted: (() -> Void)?

    private let accessibilityRow: PermissionRow
    private var pollTimer: Timer?
    private var autoDismissWhenGranted: Bool = true
    private var lastGranted: Bool = false

    init() {
        accessibilityRow = PermissionRow(
            title: "Accessibility",
            subtitle: "Required to inject pointer events into macOS.",
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
            requestAction: { Permissions.requestAccessibility() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "InkBridge Permissions"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        let header = NSTextField(wrappingLabelWithString: "InkBridge needs Accessibility permission to drive the cursor:")
        header.font = .systemFont(ofSize: NSFont.systemFontSize)

        let footer = NSTextField(wrappingLabelWithString: "Status updates automatically. Once the row is green, this window closes and InkBridge starts.")
        footer.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [header, accessibilityRow, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Margin via constraints rather than NSStackView.edgeInsets: the row's
        // leftStack has low horizontal hugging priority so it grows to absorb
        // free space, and edgeInsets stop being honoured on the trailing side
        // once an arranged subview overflows. Pinning the stack inset from
        // the content view's edges enforces the padding deterministically.
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
        ])
        window.contentView = content
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func present(autoDismissWhenGranted: Bool) {
        self.autoDismissWhenGranted = autoDismissWhenGranted
        lastGranted = false
        refresh()
        if window?.isVisible == true && autoDismissWhenGranted && Permissions.accessibilityGranted() {
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
        let granted = Permissions.accessibilityGranted()
        accessibilityRow.setGranted(granted)
        if granted && !lastGranted {
            onAllGranted?()
            if autoDismissWhenGranted {
                stopPolling()
                window?.close()
            }
        }
        lastGranted = granted
    }
}

private final class PermissionRow: NSStackView {

    private let statusIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton(title: "Open System Settings…", target: nil, action: nil)

    private let settingsURL: URL
    private let requestAction: () -> Bool

    init(title: String, subtitle: String, settingsURL: URL, requestAction: @escaping () -> Bool) {
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
        // requestAction triggers macOS's native Accessibility prompt as a
        // side-effect when the app isn't yet trusted. That prompt has its
        // own "Open System Settings" button that deep-links to the right
        // pane — opening Settings ourselves on top of that stacks two
        // windows over the prompt and confused users in v0.1.2. Only fall
        // back to opening Settings if the app is already trusted (so no
        // prompt fires) and the user is auditing.
        if requestAction() {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
