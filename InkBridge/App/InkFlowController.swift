import AppKit
import IOKit.hid
import CoreGraphics

final class InkFlowController {

    enum ConnectionState {
        case disconnected
        case connected(name: String)
    }

    private(set) var state: ConnectionState = .disconnected {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((ConnectionState) -> Void)?

    var excalidrawMode: Bool = false {
        didSet { mvm?.excalidrawMode = excalidrawMode }
    }

    var targetDisplayID: CGDirectDisplayID? {
        didSet { applyDisplay() }
    }

    private var mvm: MacOSVirtualMouse?
    private var hid: SupernoteHID?
    private var screenChangeObserver: NSObjectProtocol?

    init() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyDisplay()
        }
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        let frame = currentDisplayFrame()
        let mvm = MacOSVirtualMouse(displayWidth: frame.width, displayHeight: frame.height)
        mvm.excalidrawMode = excalidrawMode
        let hid = SupernoteHID(mvm: mvm)

        hid.onMatched = { [weak self] device in
            self?.state = .connected(name: Self.displayName(for: device))
        }
        hid.onRemoved = { [weak self] _ in
            self?.state = .disconnected
        }

        do {
            try hid.start()
            self.mvm = mvm
            self.hid = hid
        } catch {
            NSLog("InkBridge: hid.start() failed — \(error.localizedDescription)")
            state = .disconnected
        }
    }

    func stop() {
        hid?.stop()
        hid = nil
        mvm = nil
        state = .disconnected
    }

    private func applyDisplay() {
        let frame = currentDisplayFrame()
        mvm?.displayWidth  = frame.width
        mvm?.displayHeight = frame.height
    }

    private func currentDisplayFrame() -> CGRect {
        if let id = targetDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen.frame
        }
        return NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private static func displayName(for device: IOHIDDevice) -> String {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let serial  = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        switch (product, serial) {
        case let (p?, s?): return "\(p) (\(s))"
        case let (p?, nil): return p
        default: return "Supernote"
        }
    }
}
