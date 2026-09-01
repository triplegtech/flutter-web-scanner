## 1.0.0

First public release, under the MIT licence. The scanner itself is not new — it
ran in production as a closed-source package for two years, and this is that
package renamed, relicensed and opened up. The version number restarts because
the repository does; the code carries every fix listed under *Earlier
releases* below.

### Added

* **Camera selection that measures instead of guessing.** Browsers expose each
  lens of a multi-camera phone as a separate `videoinput` device, so
  `CameraSelector` scores candidates on real `MediaStreamTrack` capabilities
  where the browser reports them, on the reported facing mode where it does
  not, and on label keywords in seven languages as a last resort.
* **Detections confirmed across frames.** `DetectionStabilizer` validates every
  decode — check digit, length, format, your own guard — and requires a
  confirmation streak before `onDetect` fires, so a half-covered 1D symbol
  cannot report a structurally valid but wrong payload.
* **Two engines.** The browser's native `BarcodeDetector`, ZXing-JS, or
  `ScanEngine.auto` to pick per browser.
* **Typed failures.** `ScannerFailure` carries a `ScannerFailureKind`, and
  `isRetryable` decides whether a retry is worth offering.
* **Copy in English, Portuguese and Spanish**, resolved from the app `Locale`
  or replaced wholesale.
* **Still-image decoding** from `Uint8List` via `decodeBarcodeFromBytes`.

### Changed

Anyone moving over from the private `omni_qrcode_barcode_web_reader` package
needs two find-and-replaces; nothing else changed.

* **The package is `flutter_web_scanner`.** It is not on pub.dev yet, so depend
  on the repository and pin the tag:

  ```yaml
  dependencies:
    flutter_web_scanner:
      git:
        url: https://github.com/triplegtech/flutter_web_scanner.git
        ref: v1.0.0
  ```

* **`OmniWebScanner` is now `WebScanner`.** Same constructor, same parameters,
  same callbacks. Every other exported type keeps its name, and no default,
  callback or behaviour moved.
* **The browser namespace is `window.flutterWebScanner`**, and the DOM ids the
  interop layer creates are prefixed `flutter-web-scanner-`. Internal, and only
  visible to code that reached into the injected script directly —
  `window.flutterWebScanner.debug = true` is still how verbose logging is
  switched on.
* **Licensed under MIT.** The previous licence reserved all rights, which made
  the package unusable outside the organisation that wrote it.

## Earlier releases

Everything below documents `omni_qrcode_barcode_web_reader`, the closed-source
package this one was extracted from. Its version numbers are unrelated to the
numbering above; it is kept because it is where the reasoning behind the
camera-selection and validation behaviour was written down.

### 2.2.0

Fixes a bug that made every symbology unnameable on browsers without
`BarcodeDetector`, and adds the two callbacks that would have made it visible
in minutes rather than a debugging session. No breaking changes.

#### Fixed

* **The ZXing engine reported a number instead of a format name.**
  `result.getBarcodeFormat()` returns the *ordinal* of ZXing's enum, so the
  interop layer was sending `"7"` where Dart expected `"EAN_13"`. Every read
  therefore parsed to `BarcodeFormat.unknown`, which was invisible until a
  `ScanValidation.allowedFormats` set was supplied — at which point it rejected
  *every* decode while the preview stayed live and no failure was raised.
  Safari has no `BarcodeDetector` to fall back on, so this hit iOS hardest;
  `ScanEngine.native` was never affected. Both the live stream and
  `decodeBarcodeFromBytes` were reporting ordinals, and both are fixed.

#### Added

* `OmniWebScanner.onRawDecode` and `ScannerController.onRawDecode` hand over
  every decode the engine produced with nothing applied to it — no checksum
  check, no format filter, no confirmation streak, no cooldown. A code held in
  frame arrives once per decoded frame. `RawDecode.rawFormat` carries the
  symbology name exactly as the engine spelled it, which is the only way to
  tell a format this package does not model from one nothing could parse.
* `OmniWebScanner.onReject` and `ScannerController.onReject` report the
  decodes validation discarded, as a `ScanRejection` naming the rule and the
  threshold that was missed. Rejection is the one failure mode that raises no
  `ScannerFailure`: a scanner rejecting every frame is indistinguishable from
  one that is not decoding at all, and this is what separates them.
* `ScannerOverlayStyle.squareCutOut` frames the preview in a square derived
  from the preview's shorter axis, rather than a band of fixed height.
  `ScannerOverlayStyle.cutOutSizeFor` exposes the resulting size.

#### Changed

* **`validation` can be replaced on a live scanner.** It is applied downstream
  of the decoder, so new rules are handed to the running session instead of
  reopening the camera. This matters most for `ScanValidation.guard`: a closure
  written inside `build` is a new object on every rebuild — including the
  rebuild a caller does to show the code they just scanned — and restarting the
  camera for that blanked the preview after every read. Confirmation streaks
  and cooldowns survive the swap, so new rules cannot resurface a code that was
  just emitted.
* **`CameraPreferences`, `ScanValidation` and `ScannerOverlayStyle` now
  implement `==` and `hashCode`.** `OmniWebScanner` compares these to decide
  whether to reopen the camera, and identity comparison meant
  `cameraPreferences: CameraPreferences()` written inside a build method tore
  the session down and back up on every rebuild — which reads as a scanner that
  has stopped decoding. On `ScannerOverlayStyle` it also stops the dimmed area
  repainting every frame. `guard` is still compared by identity, because a
  closure cannot be compared any other way; hoist it to a top-level or static
  function to hold it still.
* **The default overlay changed shape.** `ScannerOverlayStyle()` now defaults
  to the band the 1D modes use rather than the previous 0.85 × 330 window, and
  `forMode` picks `squareCutOut` for 2D modes instead of varying the
  measurements. The measurements match the OMNI mobile app, so the two framings
  agree. Callers who passed their own values are unaffected.

### 2.1.0

Performance work on the live preview, plus the knobs to tune it. No breaking
changes: everything below is additive or fixes behaviour that was already
wrong.

#### Decoding

* `CameraPreferences.decodeInterval` sets the idle gap left between decode
  attempts, 100 ms by default. It is a gap and not a period, so it bounds how
  much of the main thread decoding can take — which matters because decoding
  runs on the same thread that renders the page.
* `CameraPreferences.roiWidthFactor` and `roiHeightFactor` restrict decoding to
  a centred fraction of the *visible* preview. The parts of each frame that
  `object-fit: cover` pushes outside the widget were never aimable and are now
  always discarded, so `1.0` means everything the user can see rather than the
  whole sensor frame.
* `CameraPreferences.tryHarder` exposes ZXing's `TRY_HARDER`. It stays on for
  QR codes, where a single-pass detector makes it cheap.
* `CameraPreferences.forMode(ScanMode.barcode)` now turns `tryHarder` off and
  decodes the middle 50% of the preview's height at full width. ZXing's
  `OneDReader` answers `TRY_HARDER` by scanning every row of the region instead
  of fifteen and then repeating the search on a rotated copy, once per enabled
  symbology; ten times a second on the render thread, that is what made barcode
  mode stall the page. The band that is still read is the one the mode's own
  overlay tells the user to aim at, at the full width a long code needs.

#### Overlay

* The dimming is drawn as a single subtracted path instead of a `saveLayer`
  with a `dstOut` erase. CanvasKit answers a `saveLayer` by allocating a
  viewport-sized texture, rendering into it and compositing it back, on every
  paint; the same picture now comes from one `drawPath`.
* The sweep line is an ordinary box behind a `RepaintBoundary`, moved by a
  transform, rather than a `CustomPainter` re-rasterising a cut-out-sized
  picture sixty times a second for as long as the camera is open.
* The line sweeps the framing window edge to edge. It ran from just outside the
  top to a fifth short of the bottom, and left the frame altogether whenever
  `cutOutBottomOffset` was non-zero.
* The window's geometry is decided once and shared by the shape and the line,
  so the two cannot drift, and it is clamped so `cutOutBottomOffset` can no
  longer lift the window off the top of a short preview and take the upper
  corner brackets with it.
* `ScannerOverlayStyle.overlayColor` now defaults to `0x8F000000`. The previous
  `0xBF000000` had its alpha applied twice by the `saveLayer`, so `0x8F` is
  what 2.0.0 actually put on screen: the default changed, the appearance did
  not. A custom `overlayColor` is now rendered at exactly the alpha given.

#### Camera selection

* `ScanDistance.near` no longer promotes an ultra-wide lens on its label alone.
  iOS switches to that lens for macro inside its camera app and never through
  `getUserMedia`, and most Android ultra-wides are fixed-focus — so the lens
  being ranked above the main one was the one that could not focus on a code
  held close, and scanning a barcode picked a worse lens than scanning a QR
  code did. A `macro` label still ranks first, by a margin small enough for a
  measured focus distance to overturn it.

### 2.0.0

A rewrite of the scanning pipeline. See the migration table in the README.

#### Breaking

* The minimum supported SDK is now Flutter 3.41.4 / Dart 3.11, up from
  Flutter 3.27 / Dart 3.6.
* `injectOmniWebReaderWebDependencies()` is gone — the interop script is
  injected lazily on first use, so there is nothing to call before `runApp`.
* `onError` now receives a typed `ScannerFailure` (with a `ScannerFailureKind`)
  instead of a `String?`, so callers can branch on *why* scanning failed.
* `ScanMode.Barcode` / `ScanMode.QrCode` are now `ScanMode.barcode` /
  `ScanMode.qrCode`, joined by `ScanMode.all`.
* `onDetect` fires once per confirmed, validated detection rather than on every
  decoded frame.
* The overlay's individual styling parameters were replaced by
  `ScannerOverlayStyle`, or `overlayBuilder` for full control.
* The `fit` parameter was removed; size the scanner with `width` / `height`.
* The `js` and `get` dependencies were dropped.

#### Camera selection

* Devices are now scored on measured capabilities — minimum focus distance,
  sensor size, focus modes — read from a live track, with label keywords used
  only where the browser reports nothing else.
* Candidate cameras are briefly probed before one is committed to
  (`CameraPreferences.probeCapabilities`), which is the only way to learn a
  lens's minimum focus distance.
* `ScanDistance.near` / `normal` / `auto` states the intent instead of
  hardcoding a lens per platform; the iOS-specific ultra-wide filter and the
  Android alphabetical re-sort are gone.
* Front cameras are ranked last rather than dropped, so a device whose only
  camera faces the user can still scan.
* Capture resolution, frame rate, continuous focus, zoom and torch are
  requested explicitly; browsers otherwise default to 640x480, at which a 1D
  barcode at arm's length cannot be decoded.

#### Reading and validation

* Check digits are verified for EAN-8/13, UPC-A/E and ITF-14; a payload that fails
  its own checksum is treated as a misread and never surfaced.
* Reads are confirmed across frames within a time window, with a per-value
  cooldown, replacing the 1-second same-value debounce.
* `allowedFormats`, `minLength` and an application-supplied `guard` are applied
  before a result is emitted.
* Added `ScanEngine.native` and `ScanEngine.auto` to use the browser's
  `BarcodeDetector` where it exists.
* `decodeBarcodeFromBytes` reports the symbology the engine actually found
  instead of a hardcoded `EAN-13`, and applies the same validation as the live
  scanner.

#### Lifecycle and API

* Added `ScannerController` for callers that need to drive start/stop or
  inspect the ranked camera list, and `ScannerState` as a sealed hierarchy.
* Browser access sits behind a `ScannerPlatform` seam, which is what lets the
  package compile — and be tested — off the web.
* Overlapping starts, and sessions that finish after a newer start began, no
  longer leak a camera track.
* User-facing copy is resolved from the app's `Locale` (English, Portuguese,
  Spanish) and can be replaced with `ScannerLocalizations`.

#### Tooling

* 225 unit and widget tests, at 89% line coverage.
* CI runs formatting, analysis, the test suite with an 80% coverage floor, the
  suite again on the minimum supported SDK, and a web build of the example.
* Publishing happens on merge to `main` when `pubspec.yaml` carries a version
  pub.dev does not have yet, gated on those checks; the release tag is created
  afterwards as a record.
* `example/` is now a runnable Flutter Web app.

### 1.1.4
* Fix update js util package and related code

### 1.1.3
* Feat add new qr code and barcode overlay widgets

### 1.1.2
* Fix camera filtering for phones without angular cameras

### 1.1.1
* Fix scanner erro screen
* Retry button option for loading the scanner

### 1.1.0

* Fix camera selection for iOS devices for close range scan
* Adds support to file scan

### 1.0.9

* Fix camera selection for iOS devices for close range scan

### 1.0.8

* Improves camera selection for iOS devices for close range scan

### 1.0.7

* Improves camera selection for mobile devices

### 1.0.6

* Improves camera selection for mobile devices

### 1.0.5

* Removing js script changes

### 1.0.4

* Improve scanner widget if clauses

### 1.0.3

* Improve barcode script for iOS devices

### 1.0.2

* Improve permission handling
* Fix changelog version history order

### 1.0.1

*  Fix minimum version

### 1.0.0

*  Fix documentation
*  Fix placeholder alignment

### 0.0.7-beta

*  Improving camera selection for android devices

### 0.0.6-beta

*  Improving camera selection

### 0.0.5-beta

*  Testing camera selection

### 0.0.4-beta

*   Add the scanner.js
*   Fix rendering problems

### 0.0.3-beta

*   Fix initialize error
*   Improve documentation

### 0.0.2-beta

*   Introduced a usage example

### 0.0.1-beta

*   **Initial Public Release**
*   Introduced the `omni_qrcode_barcode_web_reader` package, providing a solution for integrating camera-based barcode and QR code scanning directly within Flutter Web applications.
*   Core component: `ScannerWidget`, which utilizes `HtmlElementView` and JavaScript interoperability (`package:js`) to access `navigator.mediaDevices.getUserMedia` and the ZXing-JS decoding library.
*   **Functionality:**
    *   Displays live camera feed within the Flutter widget tree.
    *   Detects various barcode formats and QR codes.
    *   Provides scan results (`value` and `format`) via the mandatory `onDetect` callback.
    *   Reports errors (permissions, camera access, JS issues) through the optional `onError` callback.
*   **User Interface:**
    *   Features a customizable overlay to guide users.
    *   Offers `ScanMode.QrCode` and `ScanMode.Barcode` to tailor the overlay's central cutout shape.
    *   Extensive customization parameters for overlay color, border/bracket appearance (color, width, length), cutout size, and corner rounding.
    *   Supports displaying a custom `placeholder` widget during the camera initialization phase.
*   **Setup:** Requires adding script tags for the ZXing-JS library and the package's `barcode_scanner.js` interop file to the project's `web/index.html`.




