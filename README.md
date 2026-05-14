# InkBridge

Unofficial macOS support for the Supernote InkFlow feature. Drives the Mac cursor with pressure and tilt from a Supernote stylus over USB, without needing the Supernote Partner app running.

![InkBridge menu bar](screenshot.png)

## Use

1. Build and launch `InkBridge.app`
2. Grant Accessibility and Input Monitoring when prompted
3. Plug in the Supernote, open InkFlow on the device

## Build

```
xcodegen generate
open InkBridge.xcodeproj
```

Requires Xcode 15+ and macOS 13+. Ad-hoc signed by default.

## Not affiliated with Ratta / Supernote.
