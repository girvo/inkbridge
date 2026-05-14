import Foundation
import CoreGraphics

final class Preferences {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let excalidrawMode  = "excalidrawMode"
        static let targetDisplayID = "targetDisplayID"
    }

    var excalidrawMode: Bool {
        get { defaults.bool(forKey: Key.excalidrawMode) }
        set { defaults.set(newValue, forKey: Key.excalidrawMode) }
    }

    var targetDisplayID: CGDirectDisplayID? {
        get {
            let n = defaults.integer(forKey: Key.targetDisplayID)
            return n == 0 ? nil : CGDirectDisplayID(n)
        }
        set {
            if let id = newValue {
                defaults.set(Int(id), forKey: Key.targetDisplayID)
            } else {
                defaults.removeObject(forKey: Key.targetDisplayID)
            }
        }
    }
}
