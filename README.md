# Flutter Web Scanner

[![CI](https://github.com/triplegtech/flutter_web_scanner/actions/workflows/ci.yml/badge.svg)](https://github.com/triplegtech/flutter_web_scanner/actions/workflows/ci.yml)
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

The package is not on pub.dev yet, so depend on the repository directly. Pin a
tag rather than a branch — every release is tagged `v<version>`:

```yaml
dependencies:
  flutter_web_scanner:
    git:
      url: https://github.com/triplegtech/flutter_web_scanner.git
      ref: v1.0.0
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
WebScanner(
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

### `WebScanner`

| Parameter | Purpose |
|---|---|
| `onDetect` | Called with each confirmed `BarcodeResult`. |
| `onError` | Called with a typed `ScannerFailure` when the scanner stops. |
| `onRawDecode` | Called with every decode the engine produced, with no validation, confirmation or cooldown applied. See below. |
| `onReject` | Called with a `ScanRejection` naming the rule that discarded a decode. See below. |
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
WebScanner(
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

### Seeing what the engine actually returned

`onDetect` gives you the reads the package trusts. Two callbacks give you the
ones it does not, which is what you need when a code that should scan does not:
a scanner rejecting every frame raises no `ScannerFailure` and looks exactly
like one that is not decoding at all.

```dart
WebScanner(
  // Every decode, with nothing applied: no checksum check, no format filter,
  // no confirmation streak, no cooldown. A code held in frame arrives once per
  // decoded frame, so treat this as a stream — do not setState from it.
  onRawDecode: (decode) {
    print('${decode.value} — engine said "${decode.rawFormat}"');
  },
  // Only the decodes validation threw away, with the rule that did it.
  onReject: (rejection) {
    print('${rejection.reason.name}: ${rejection.message}');
  },
  onDetect: handleResult,
)
```

`RawDecode.rawFormat` is the symbology name exactly as the engine spelled it,
before `BarcodeFormat.parse` normalises it — the field to read when
`decode.format` comes back as `BarcodeFormat.unknown`, since that value cannot
otherwise distinguish a symbology this package does not model from a name
nothing could parse.

### Camera selection

```dart
WebScanner(
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

## Coming from `omni_qrcode_barcode_web_reader`

1.0.0 is the closed-source package this one grew out of, renamed and opened up.
Its numbering is unrelated to this one's, and the tables below are for anyone
migrating off it — a new project can skip this section.

From its **2.x**, two find-and-replaces cover the whole move:

| omni 2.x | flutter_web_scanner |
|---|---|
| `omni_qrcode_barcode_web_reader` | `flutter_web_scanner` — the package, the import and the repository. |
| `OmniWebScanner(...)` | `WebScanner(...)` — same constructor, same parameters. |

Every other exported type keeps its name, and no default, callback or
behaviour moved.

From its **1.x**, the API changed shape first — that work landed in its 2.0.0
and is inherited here:

| omni 1.x | flutter_web_scanner |
|---|---|
| The pre-`runApp` dependency-injection call | Removed; injection is lazy. |
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

## Releasing

One branch per version, and the release comes out of the merge:

1. Branch off `main` — `release/1.1.0` reads best, but the name is not enforced.
2. Bump `version:` in `pubspec.yaml` and add the matching `## 1.1.0` section at
   the **top** of `CHANGELOG.md`. That section becomes the release body, so
   write it for whoever will read the release page.
3. Open a PR and let the gates run.
4. Merge. CI re-runs analyze and the tests at the merge commit, tags it
   `v1.1.0`, and creates the GitHub release from the CHANGELOG section.

Merges that do not change the version release nothing — the job checks whether
`v<version>` is already tagged and stops there — so an unrelated PR costs one
short job. Do not create tags by hand.

The version branch is meant to stay in the repository after the merge; nothing
in CI deletes it. Keep GitHub's *Settings → General → Automatically delete head
branches* switched **off**, or the merge will remove it for you.

Publishing to pub.dev is not part of this flow yet.

## License

MIT — see [LICENSE](LICENSE).
