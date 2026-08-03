## 2.0.0

A rewrite of the scanning pipeline. See the migration table in the README.

### Breaking

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

### Camera selection

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

### Reading and validation

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

### Lifecycle and API

* Added `ScannerController` for callers that need to drive start/stop or
  inspect the ranked camera list, and `ScannerState` as a sealed hierarchy.
* Browser access sits behind a `ScannerPlatform` seam, which is what lets the
  package compile — and be tested — off the web.
* Overlapping starts, and sessions that finish after a newer start began, no
  longer leak a camera track.
* User-facing copy is resolved from the app's `Locale` (English, Portuguese,
  Spanish) and can be replaced with `ScannerLocalizations`.

### Tooling

* 225 unit and widget tests, at 89% line coverage.
* CI runs formatting, analysis, the test suite with an 80% coverage floor, the
  suite again on the minimum supported SDK, and a web build of the example.
* Publishing is gated on the tests, and on the tag matching `pubspec.yaml`.
* `example/` is now a runnable Flutter Web app.

## 1.1.4
* Fix update js util package and related code

## 1.1.3
* Feat add new qr code and barcode overlay widgets

## 1.1.2
* Fix camera filtering for phones without angular cameras

## 1.1.1
* Fix scanner erro screen
* Retry button option for loading the scanner

## 1.1.0

* Fix camera selection for iOS devices for close range scan
* Adds support to file scan

## 1.0.9

* Fix camera selection for iOS devices for close range scan

## 1.0.8

* Improves camera selection for iOS devices for close range scan

## 1.0.7

* Improves camera selection for mobile devices

## 1.0.6

* Improves camera selection for mobile devices

## 1.0.5

* Removing js script changes

## 1.0.4

* Improve scanner widget if clauses

## 1.0.3

* Improve barcode script for iOS devices

## 1.0.2

* Improve permission handling
* Fix changelog version history order

## 1.0.1

*  Fix minimum version

## 1.0.0

*  Fix documentation
*  Fix placeholder alignment

## 0.0.7-beta

*  Improving camera selection for android devices

## 0.0.6-beta

*  Improving camera selection

## 0.0.5-beta

*  Testing camera selection

## 0.0.4-beta

*   Add the scanner.js
*   Fix rendering problems

## 0.0.3-beta

*   Fix initialize error
*   Improve documentation

## 0.0.2-beta

*   Introduced a usage example

## 0.0.1-beta

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




