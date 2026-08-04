# Omni QR Code / Barcode Web Reader

[![pub version](https://img.shields.io/pub/v/omni_qrcode_barcode_web_reader.svg)](https://pub.dev/packages/omni_qrcode_barcode_web_reader)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Flutter Platform](https://img.shields.io/badge/Platform-Web-blue)

Camera-based QR code and barcode scanning for **Flutter Web**, built around two
problems that make browser scanning harder than it looks: picking the right lens
on a multi-camera phone, and telling a real read apart from a plausible misread.

## Features

* **Capability-driven camera selection.** Browsers expose every lens of a phone
  as a separate device with only a localised label to tell them apart. The
  selector scores devices on measured focus distance and sensor size where the
  browser reports them, and on label keywords (English, Portuguese, Spanish,
  French, German, Italian, Dutch) where it does not.
* **Validated detections.** A decode is checked (check digit, length, format,
  your own guard) and confirmed across frames before `onDetect` fires, so a
  half-covered barcode cannot report a structurally valid but wrong payload.
* **Two engines.** The browser's native `BarcodeDetector` where available, ZXing
  everywhere else, or `ScanEngine.auto` to pick per browser.
* **Typed failures.** `ScannerFailure` carries a `ScannerFailureKind`, so a
  denied permission and a camera held by another tab lead to different UI.
* **Built-in copy in English, Portuguese and Spanish**, resolved from the app's
  `Locale`, or replaced wholesale with your own.
* **Still-image decoding** from `Uint8List` via `decodeBarcodeFromBytes`.

## Platform support

Flutter Web only (`>=3.41.4`, Dart `^3.11.0`). The package relies on
`navigator.mediaDevices`, `HtmlElementView` and JS interop; on any other target
every call fails with `ScannerFailureKind.unsupportedPlatform`.

Camera access also requires a **secure context**: HTTPS or `localhost`. Testing
from a LAN IP surfaces as `ScannerFailureKind.insecureContext`.

## Getting started

### 1. Install

```yaml
dependencies:
  omni_qrcode_barcode_web_reader: ^2.1.0
```

### 2. Load a decoding engine

Unless you target only browsers that implement `BarcodeDetector`, add the
ZXing-JS script to `web/index.html`:

```html
<head>
  <script src="https://unpkg.com/@zxing/library@latest/umd/index.min.js"></script>
</head>
```

The package's own interop script is bundled as an asset and injected on first
use — there is nothing to call before `runApp`.

### 3. Scan

```dart
OmniWebScanner(
  scanMode: ScanMode.barcode,
  engine: ScanEngine.auto,
  showRetryButton: true,
  onDetect: (result) {
    print('${result.format.name}: ${result.value}');
  },
  onError: (failure) {
    if (failure.kind == ScannerFailureKind.permissionDenied) {
      // Show your own "allow camera access" prompt.
    }
  },
)
```

`onDetect` fires once per confirmed detection, not once per decoded frame.

## Configuration

### `OmniWebScanner`

| Parameter | Purpose |
|---|---|
| `onDetect` | Called with each confirmed `BarcodeResult`. |
| `onError` | Called with a typed `ScannerFailure` when the scanner stops. |
| `scanMode` | `barcode`, `qrCode` or `all`. Drives overlay shape, format hints, camera and validation defaults. |
| `engine` | `zxing` (default), `native` or `auto`. |
| `validation` | Rules a decode must pass. See below. |
| `cameraPreferences` | How the camera is chosen and configured. |
| `overlayStyle` / `overlayBuilder` | Restyle or fully replace the framing overlay. |
| `placeholder` | Shown while the camera starts. |
| `errorBuilder` | Replaces the built-in error presentation. |
| `showRetryButton` | Offers a retry on failures where one could succeed. |
| `localizations` | Your own copy, overriding the app locale. |
| `controller` | An externally owned `ScannerController`, for driving start/stop or inspecting the ranked camera list. You dispose it. |

### Validation

```dart
OmniWebScanner(
  validation: ScanValidation(
    requireChecksum: true,        // verify EAN/UPC/ITF check digits
    confirmations: 2,             // identical reads before emitting
    cooldown: Duration(seconds: 2),
    minLength: 8,
    allowedFormats: {BarcodeFormat.ean13},
    guard: (value, format) => value.startsWith('789'),
  ),
  onDetect: handleResult,
)
```

Presets: `ScanValidation.none` (emit on first decode), the per-mode default,
and `ScanValidation.strict` (three confirmations).

### Camera selection

```dart
OmniWebScanner(
  cameraPreferences: CameraPreferences(
    distance: ScanDistance.near,  // near | normal | auto
    idealWidth: 1920,
    probeCapabilities: true,      // measure lenses before committing
    continuousFocus: true,
    torch: false,
  ),
  onDetect: handleResult,
)
```

`distance` is the important one. `near` prioritises the smallest reachable
minimum focus distance — the ultra-wide lens on most phones. `normal`
prioritises pixels on target. `auto` prefers the main lens but switches when
probing shows it cannot focus close enough.

Probing briefly opens candidate cameras to read their real capabilities. It
costs roughly 200–400 ms per camera and makes selection far more accurate than
any label guess; set `probeCapabilities: false` when startup latency matters
more.

### Decoding an image file

```dart
final bytes = await pickedFile.readAsBytes();
final result = await decodeBarcodeFromBytes(bytes, mode: ScanMode.barcode);
```

Returns `null` when the image holds no readable code or the read fails
validation, and throws `ScannerFailure` when the bytes themselves cannot be
processed. The MIME type is sniffed from the bytes, and the symbology reported
is the one the engine actually found.

## Migrating from 1.x

| 1.x | 2.x |
|---|---|
| `await injectOmniWebReaderWebDependencies()` before `runApp` | Removed; injection is lazy. |
| `onError: (String? message)` | `onError: (ScannerFailure failure)` — branch on `failure.kind`. |
| `ScanMode.Barcode` / `ScanMode.QrCode` | `ScanMode.barcode` / `ScanMode.qrCode`, plus `ScanMode.all`. |
| `fit` | Removed; size the scanner with `width` / `height`. |
| Overlay tuned through a dozen widget parameters | `ScannerOverlayStyle`, or `overlayBuilder` for full control. |
| `js` and `get` dependencies in your pubspec | Neither is needed. |
| `onDetect` on every decoded frame | Once per confirmed, validated detection. |
| Hardcoded `EAN-13` on file decodes | The symbology the engine reported. |
| Portuguese-only copy | Resolved from the app `Locale`; override with `localizations`. |

## Development

```bash
flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test --coverage

cd example && flutter run -d chrome   # runnable demo
cd example && ./run_device.sh         # demo over HTTPS, for a real phone
```

`run_device.sh` serves the example and exposes it through a Cloudflare Quick
Tunnel (`brew install cloudflared`). The camera needs a secure context, so the
dev server's LAN address is rejected as `insecureContext` on a phone — the
tunnel's `https://…trycloudflare.com` URL is not.

Pull requests run analysis, the full test suite with an 80% line-coverage
floor, the same suite on the minimum supported SDK, and a web build of the
example. Formatting is reported as a warning, not enforced — `dart format`
output differs between Dart releases.

Releases are automatic: merging a version bump in `pubspec.yaml` into `main`
re-runs the tests and publishes to pub.dev, then tags the commit. Merges that
do not change the version publish nothing.
