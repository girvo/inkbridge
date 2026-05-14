import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

final class SupernoteHID {
    static let VID = 0x2207
    static let PID = 0x0007

    let mvm: MacOSVirtualMouse
    let manager: IOHIDManager
    private let buf: UnsafeMutablePointer<UInt8>
    private let bufSize = 64

    var verbose: Bool = false
    var onMatched: ((IOHIDDevice) -> Void)?
    var onRemoved: ((IOHIDDevice) -> Void)?
    private var rateCount: Int = 0
    private var lastRateReport: Date = Date()
    private(set) var matchedDeviceCount: Int = 0

    init(mvm: MacOSVirtualMouse) {
        self.mvm = mvm
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
    }

    deinit {
        buf.deallocate()
    }

    func start() throws {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey  as String: SupernoteHID.VID,
            kIOHIDProductIDKey as String: SupernoteHID.PID,
        ] as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchedCallback, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback (manager, hidDeviceRemovedCallback, ctx)

        let res = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard res == kIOReturnSuccess else {
            throw NSError(domain: "IOHID", code: Int(res), userInfo: [
                NSLocalizedDescriptionKey:
                    "IOHIDManagerOpen with seize failed: 0x\(String(format:"%08x", res)). " +
                    "Open System Settings → Privacy & Security → Input Monitoring and enable InkBridge, then re-launch."
            ])
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(),
                                        CFRunLoopMode.defaultMode.rawValue)
    }

    fileprivate func handleMatched(_ device: IOHIDDevice) {
        matchedDeviceCount += 1
        print("attached: Supernote (\(matchedDeviceCount) total)")
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, bufSize, hidReportCallback, ctx)
        onMatched?(device)
    }

    fileprivate func handleRemoved(_ device: IOHIDDevice) {
        matchedDeviceCount = max(0, matchedDeviceCount - 1)
        print("detached: Supernote (\(matchedDeviceCount) remaining)")
        onRemoved?(device)
    }

    fileprivate func onReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard reportID == 2, length >= 10 else { return }
        let buttons  = report[1]
        let pressure = UInt16(report[2]) | (UInt16(report[3]) << 8)
        let x        = UInt16(report[4]) | (UInt16(report[5]) << 8)
        let y        = UInt16(report[6]) | (UInt16(report[7]) << 8)
        let tx       = Int8(bitPattern: report[8])
        let ty       = Int8(bitPattern: report[9])

        mvm.handle(buttons: buttons, rawX: x, rawY: y,
                   rawPressure: pressure, tiltX: tx, tiltY: ty)

        rateCount += 1
        if verbose {
            let now = Date()
            if now.timeIntervalSince(lastRateReport) >= 1.0 {
                print("rate: \(rateCount) reports/sec")
                rateCount = 0
                lastRateReport = now
            }
        }
    }

    func stop() {
        IOHIDManagerClose(manager, 0)
    }
}

private let hidDeviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let ctx = context else { return }
    Unmanaged<SupernoteHID>.fromOpaque(ctx).takeUnretainedValue().handleMatched(device)
}

private let hidDeviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let ctx = context else { return }
    Unmanaged<SupernoteHID>.fromOpaque(ctx).takeUnretainedValue().handleRemoved(device)
}

private let hidReportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    guard let ctx = context else { return }
    Unmanaged<SupernoteHID>.fromOpaque(ctx).takeUnretainedValue()
        .onReport(reportID: reportID, report: report, length: length)
}
