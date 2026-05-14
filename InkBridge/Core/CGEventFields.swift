import CoreGraphics

extension CGEventField {
    static let f_mouseClickState        = CGEventField(rawValue:  1)!
    static let f_mousePressure          = CGEventField(rawValue:  2)!
    static let f_mouseButtonNumber      = CGEventField(rawValue:  3)!
    static let f_mouseSubtype           = CGEventField(rawValue:  7)!
    static let f_tabletPointPressure    = CGEventField(rawValue: 19)!
    static let f_tabletTiltX            = CGEventField(rawValue: 20)!
    static let f_tabletTiltY            = CGEventField(rawValue: 21)!
    static let f_tabletDeviceID         = CGEventField(rawValue: 24)!
    static let f_tabletProxDeviceID     = CGEventField(rawValue: 31)!
    static let f_tabletProxCapMask      = CGEventField(rawValue: 36)!
    static let f_tabletProxPointerType  = CGEventField(rawValue: 37)!
    static let f_tabletProxEnterProx    = CGEventField(rawValue: 38)!
}
