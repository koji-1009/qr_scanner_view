# qr_scanner_view_example

A runnable demo of [`qr_scanner_view`](../).

It shows the full widget in use:

- A live `QrScannerView` filling the screen, with `onDetect` and a `frames`
  listener.
- An overlay (`overlayBuilder`) that paints a constant reticle plus a green
  outline around every detected code, using the normalized `Barcode.corners`.
- `placeholderBuilder` while the camera is starting and `errorBuilder` for the
  permission / error states.
- A control panel wired to the controller: zoom slider, torch toggle, lens
  cycling (`auto` / `back` / `front`) and a `cover` / `contain` fit switch.
- The last decoded value and its `ParsedValue` interpretation.

The panel uses fixed-height rows on purpose: resizing the preview rebinds the
CameraX camera on Android (see the package README's "keep the view's size
stable" note).

## Run

```sh
cd example
flutter run
```

iOS needs a camera and `NSCameraUsageDescription` (already set in the example's
`Info.plist`); Android requests the permission at first scan.
