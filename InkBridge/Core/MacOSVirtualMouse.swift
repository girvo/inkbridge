import Foundation
import CoreGraphics

final class MacOSVirtualMouse {
    private let deviceMagic: Int64 = Int64(bitPattern: 0x499a38caef8574fd)
    private let capabilityMask: Int64 = 0x5c7

    private let eventSource: CGEventSource
    private var cachedEvent: CGEvent

    var displayWidth:  CGFloat
    var displayHeight: CGFloat

    var enableTabletFields: Bool = true
    var logEvents: Bool = false

    var proximityIdleThreshold: TimeInterval = 0.2

    var excalidrawMode: Bool = false
    var eraserEnterKey: CGKeyCode = KeyCodes.zero
    var eraserLeaveKey: CGKeyCode = KeyCodes.seven

    private var currButtons: UInt64 = 0
    private var prevButtons: UInt64 = 0
    private var pendingX: Float? = nil
    private var pendingY: Float? = nil
    private var pressure: Float = 0
    private var tiltX: Double = 0
    private var tiltY: Double = 0
    private var isEraser:    Bool = false
    private var isSetEraser: Bool = false
    private var lastButton:  Int = 0
    private var lastSampleTime: Date = .distantPast
    private var lastEraserKey: Bool = false

    init(displayWidth: CGFloat, displayHeight: CGFloat) {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            fatalError("CGEventSourceCreate failed.")
        }
        guard let ev = CGEvent(source: src) else {
            fatalError("CGEventCreate failed.")
        }
        self.eventSource  = src
        self.cachedEvent  = ev
        self.displayWidth  = displayWidth
        self.displayHeight = displayHeight
    }

    func handle(buttons: UInt8, rawX: UInt16, rawY: UInt16,
                rawPressure: UInt16, tiltX: Int8, tiltY: Int8)
    {
        let tip     = (buttons & 0x01) != 0
        let inRange = (buttons & 0x02) != 0
        // bit3 (Invert) latches the moment the pen is flipped (hover or contact);
        // bit2 (Eraser-in-contact) fires only during contact. See PLAN.html §3a.
        let eraser  = (buttons & 0x08) != 0
        let barrel  = (buttons & 0x10) != 0

        let now = Date()
        let idle = now.timeIntervalSince(lastSampleTime)
        lastSampleTime = now

        if enableTabletFields && idle > proximityIdleThreshold {
            isSetEraser = !eraser
        }

        self.isEraser = eraser
        self.tiltX = Double(tiltX)
        self.tiltY = Double(tiltY)
        self.pressure = Float(rawPressure) / 4095.0

        if excalidrawMode && eraser != lastEraserKey {
            lastEraserKey = eraser
            sendKeystroke(virtualKey: eraser ? eraserEnterKey : eraserLeaveKey)
            if logEvents {
                let k = eraser ? eraserEnterKey : eraserLeaveKey
                print("  excalidraw: keystroke 0x\(String(format:"%02x", k)) (\(eraser ? "→eraser" : "→pen"))")
            }
        }

        setPendingPosition(x: Float(rawX) / 32767.0, y: Float(rawY) / 32767.0)
        applyEraserStateChange(eraser: eraser)

        guard inRange else { return }

        var desired: UInt64 = 0
        if tip { desired |= (barrel ? (1 << 1) : (1 << 0)) }

        let toClear = currButtons & ~desired
        let toSet   = desired   & ~currButtons
        if toClear & (1 << 1) != 0 { currButtons &= ~(UInt64(1) << 1) }
        if toClear & (1 << 0) != 0 { currButtons &= ~(UInt64(1) << 0) }
        if toSet   & (1 << 0) != 0 { currButtons |=  (UInt64(1) << 0) }
        if toSet   & (1 << 1) != 0 { currButtons |=  (UInt64(1) << 1) }

        flushPendingPosition()
    }

    private func setPendingPosition(x: Float, y: Float) {
        pendingX = x; pendingY = y
    }

    private func applyEraserStateChange(eraser: Bool) {
        guard enableTabletFields else { return }
        guard eraser != isSetEraser else { return }
        isSetEraser = eraser
        let pointerType: Int64 = eraser ? 3 : 1
        if let prox = CGEvent(source: eventSource) {
            prox.type = .tabletProximity
            prox.setIntegerValueField(.f_tabletProxEnterProx,   value: 1)
            prox.setIntegerValueField(.f_tabletProxPointerType, value: pointerType)
            prox.setIntegerValueField(.f_tabletProxCapMask,     value: capabilityMask)
            prox.setIntegerValueField(.f_tabletProxDeviceID,    value: deviceMagic)
            prox.post(tap: .cghidEventTap)
        }
        cachedEvent.setIntegerValueField(.f_mouseSubtype,          value: 2)
        cachedEvent.setIntegerValueField(.f_tabletProxEnterProx,   value: 1)
        cachedEvent.setIntegerValueField(.f_tabletProxPointerType, value: pointerType)
        cachedEvent.setIntegerValueField(.f_tabletProxCapMask,     value: capabilityMask)
        cachedEvent.setIntegerValueField(.f_tabletProxDeviceID,    value: deviceMagic)
    }

    private func flushPendingPosition() {
        if currButtons != prevButtons {
            postPenStateEvent(prev: prevButtons, curr: currButtons)
            prevButtons = currButtons
            return
        }
        guard let px = pendingX, let py = pendingY else { return }
        pendingX = nil; pendingY = nil

        let dragging = (currButtons & (UInt64(1) << lastButton)) != 0
        let type: CGEventType = dragging ? dragType(for: lastButton) : .mouseMoved
        let loc = screenPoint(x: px, y: py)
        cachedEvent.type = type
        cachedEvent.location = loc
        applyTabletPointFields(on: cachedEvent)
        cachedEvent.post(tap: .cghidEventTap)
        if logEvents { print(String(format: "  %@ at (%.1f, %.1f)", typeName(type), loc.x, loc.y)) }
        refreshCachedEvent()
    }

    private func postPenStateEvent(prev: UInt64, curr: UInt64) {
        for bit in 0..<5 {
            let pSet = ((prev >> bit) & 1) != 0
            let cSet = ((curr >> bit) & 1) != 0
            guard pSet != cSet else { continue }
            cachedEvent.type = cSet ? downType(for: bit) : upType(for: bit)
            if let px = pendingX, let py = pendingY {
                cachedEvent.location = screenPoint(x: px, y: py)
            }
            cachedEvent.setIntegerValueField(.f_mouseButtonNumber, value: Int64(bit))
            cachedEvent.setIntegerValueField(.f_mouseClickState,   value: 1)
            applyTabletPointFields(on: cachedEvent)
            cachedEvent.post(tap: .cghidEventTap)
            if logEvents {
                let loc = cachedEvent.location
                print(String(format: "  %@ at (%.1f, %.1f) bit=%d",
                             typeName(cachedEvent.type), loc.x, loc.y, bit))
            }
            refreshCachedEvent()
            lastButton = bit
        }
        if curr == 0 {
            cachedEvent.setIntegerValueField(.f_mouseButtonNumber, value: 0)
        }
    }

    private func applyTabletPointFields(on event: CGEvent) {
        guard enableTabletFields else { return }
        let p = Double(pressure)
        event.setDoubleValueField(.f_mousePressure,       value: p)
        event.setIntegerValueField(.f_mouseSubtype,       value: 1)
        event.setIntegerValueField(.f_tabletDeviceID,     value: deviceMagic)
        event.setDoubleValueField(.f_tabletPointPressure, value: p)
        event.setDoubleValueField(.f_tabletTiltX,         value: tiltX /  90.0)
        event.setDoubleValueField(.f_tabletTiltY,         value: tiltY / -90.0)
    }

    private func refreshCachedEvent() {
        if let ev = CGEvent(source: eventSource) { cachedEvent = ev }
    }

    private func sendKeystroke(virtualKey: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    private func screenPoint(x: Float, y: Float) -> CGPoint {
        CGPoint(x: CGFloat(x) * displayWidth, y: CGFloat(y) * displayHeight)
    }
    private func downType(for bit: Int) -> CGEventType {
        switch bit { case 0: return .leftMouseDown; case 1: return .rightMouseDown; default: return .otherMouseDown }
    }
    private func upType(for bit: Int) -> CGEventType {
        switch bit { case 0: return .leftMouseUp; case 1: return .rightMouseUp; default: return .otherMouseUp }
    }
    private func dragType(for bit: Int) -> CGEventType {
        switch bit { case 0: return .leftMouseDragged; case 1: return .rightMouseDragged; default: return .otherMouseDragged }
    }
    private func typeName(_ t: CGEventType) -> String {
        switch t {
        case .mouseMoved:        return "mouseMoved"
        case .leftMouseDown:     return "leftMouseDown"
        case .leftMouseUp:       return "leftMouseUp"
        case .leftMouseDragged:  return "leftMouseDragged"
        case .rightMouseDown:    return "rightMouseDown"
        case .rightMouseUp:      return "rightMouseUp"
        case .rightMouseDragged: return "rightMouseDragged"
        case .otherMouseDown:    return "otherMouseDown"
        case .otherMouseUp:      return "otherMouseUp"
        case .otherMouseDragged: return "otherMouseDragged"
        default:                 return "type(\(t.rawValue))"
        }
    }
}
