# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`omni_qrcode_barcode_web_reader` — a **Flutter Web-only** pub package that scans QR codes and barcodes from the device camera (and from image bytes) by bridging Dart to the ZXing-JS browser library. `pubspec.yaml` declares `platforms: web:`; nothing here works on mobile/desktop.

## Commands

```bash
flutter pub get
flutter analyze            # the only gate CI runs before publishing
dart pub publish --dry-run # validates package layout/version before tagging
```

There are no tests (`test/` does not exist) and no runnable example app — `example/main.dart` contains only an `ExamplePage` widget with no `main()`. To exercise changes manually you must consume the package from a separate Flutter Web app (see "Consumer setup" below).

### Publishing

`.github/workflows/dart.yml` triggers on a `v*.*.*` tag: `flutter pub get` → `flutter analyze` → `dart pub publish --force` → GitHub release. Before tagging, bump `version:` in `pubspec.yaml` and add a matching entry at the **top** of `CHANGELOG.md`.

## Architecture

Three layers, and a change to the scanning behavior usually touches all three:

1. **Dart widgets** (`lib/src/pages/`, `lib/src/widgets/`) — Flutter UI and lifecycle.
2. **JS interop bindings** (`lib/js_interop.dart`) — `@JS('name') external` declarations that bind to **global** functions on `window`.
3. **`assets/js/scanner.js`** — the actual browser code. Top-level `async function`s here become the `window` globals that layer 2 binds to.

### The JS injection mechanism (non-obvious)

`scanner.js` is shipped as a **Flutter asset**, not as a script tag. The consuming app must call:

```dart
await injectOmniWebReaderWebDependencies(); // lib/omni_qrcode_barcode_web_reader.dart
```

which `rootBundle.loadString`s the asset and appends it as an inline `<script id="omni-web-scanner-interop-script">` to `<head>` (idempotent via the id check).

Consequences to keep in mind:
- **Adding a JS function requires two edits**: a top-level function in `assets/js/scanner.js` *and* a matching `@JS('fnName') external` in `lib/js_interop.dart`.
- `scanner.js` starts with `const ZXing = window.ZXing`, captured **at injection time**. ZXing-JS itself is *not* bundled — the consuming app must load it from CDN in `web/index.html` before Flutter starts. If it's missing, every call fails with "ZXing library not loaded".
- `window.scannerState` is a **single global object**, so only one scanner can run at a time even though `startCamera`/`stopCamera` take a `viewId`.

### Camera selection heuristic (`lib/src/services/camera_service.dart`)

The most intricate logic in the package, and the source of most of the CHANGELOG history. It exists because browsers expose multi-lens phone cameras as separate `videoinput` devices with only free-text labels, and picking the wrong lens breaks close-range barcode focus.

- Devices are scored from `label` keywords in **both English and Portuguese**. **Lower score = higher priority.**
- Front cameras score `999` and are **dropped entirely** from the returned list.
- Back cameras start at `10`; a special-lens keyword (wide/tele/depth/macro) adds `+5`. Generic/unlabeled devices get `50`/`55`. A sole device gets `5`.
- After sorting by score, platform-specific overrides apply via `GetPlatform` (this is the **only** reason `get` is a dependency): **Android** re-sorts alphabetically by label; **iOS** hard-filters to `ultra wide` / `ultra angular` devices when any exist.
- `OmniWebScanner` always takes `devices.first`; there is no camera picker UI.

Any change here needs real-device verification across iOS/Android browsers — the scoring cannot be validated from the code alone.

### Widget flow

`OmniWebScanner` (`src/pages/scanner_page.dart`) owns camera enumeration, permission state, and error/loading branches. Once a camera is chosen it renders `ScannerWidget` keyed on `deviceId`, which:

- registers a unique platform view (`ui.platformViewRegistry.registerViewFactory`) with a `viewId` derived from `microsecondsSinceEpoch`, backed by a plain `<div>`;
- starts the camera in a `postFrameCallback` — the JS side polls with `waitForElement` (5s timeout) because Flutter mounts the platform view asynchronously;
- **debounces repeated detections**: the same value within 1 second is swallowed before `onDetect` fires;
- restarts the camera in `didUpdateWidget` when `deviceId` changes, and calls `stopCamera` in `dispose`.

Overlays (`BarcodeOverlayWidget` / `QrCodeOverlayWidget`, selected by `ScanMode`) are pure Flutter, stacked over the `HtmlElementView`. They share `ScannerOverlayShape` (a `ShapeBorder` that punches a cutout in a dimmed layer) and `ScannerLinePainter` (animated sweep line). Overlay sizing is hardcoded, not parameterized.

### File-based decoding

`decodeBarcodeFromBytes` (`src/services/scan_service.dart`) sniffs the MIME type from magic bytes (`mimetype_helper.dart`), wraps the data in a `web.File`, and hands it to JS `decodeBarcodeFromImage`. Note the JS side returns only `{ value }`, so the Dart side **hardcodes `format: 'EAN-13'`** regardless of the real format.

## Conventions and known quirks

- **Two interop styles coexist.** `lib/js_interop.dart` and `scan_service.dart` use modern `dart:js_interop` + `package:web`; `scanner_widget.dart`, the injection function, and `language_helper.dart` use legacy `dart:html`. `analysis_options.yaml` silences `avoid_web_libraries_in_flutter` and `deprecated_member_use` to allow this — don't "fix" the lints, and match the style already in the file you're editing.
- **User-facing strings are hardcoded Portuguese (pt-BR)** in `scanner_page.dart`, `error_widget.dart`, and `scanner_widget.dart`. `src/helpers/language_helper.dart` (`isDeviceLanguagePortuguese`) exists but is currently unused.
- **Public API is only what `lib/omni_qrcode_barcode_web_reader.dart` exports**: `OmniWebScanner`, `ScanMode`, `decodeBarcodeFromBytes`, plus `injectOmniWebReaderWebDependencies`. Everything under `src/` is private to consumers, so moving files there is non-breaking but changing those four is.
- The JS layer logs verbosely with a `[JS]` prefix and `camera_service.dart` uses bare `print` (with `avoid_print` ignored at the top of the file) — this is intentional, since the camera heuristic is debugged from browser consoles on real devices.

## Consumer setup (what the package requires of host apps)

```html
<!-- web/index.html, inside <head> -->
<script type="text/javascript" src="https://unpkg.com/@zxing/library@latest/umd/index.min.js"></script>
```

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await injectOmniWebReaderWebDependencies();
  runApp(const MyApp());
}
```

Camera access also requires a secure context (HTTPS or `localhost`).
