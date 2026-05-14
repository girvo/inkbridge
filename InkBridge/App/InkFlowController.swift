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
        let mvm = MacOSVirtualMouse(displayFrame: frame)
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
        mvm?.displayFrame = currentDisplayFrame()
    }

    private func currentDisplayFrame() -> CGRect {
        // CGDisplayBounds returns the display's rect in global Quartz coordinates
        // (top-left origin, spanning all attached displays). This is the same
        // coordinate space CGEvent.location uses, so no AppKit-to-Quartz flip
        // is required. NSScreen.frame is AppKit coords (bottom-left) and would
        // need conversion — avoid it.
        if let id = targetDisplayID {
            let bounds = CGDisplayBounds(id)
            if bounds.size.width > 0 && bounds.size.height > 0 {
                return bounds
            }
        }
        return CGDisplayBounds(CGMainDisplayID())
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
