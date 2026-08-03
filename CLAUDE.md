# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`omni_qrcode_barcode_web_reader` — a **Flutter Web-only** pub package that scans QR codes and barcodes from the device camera (and from image bytes) by bridging Dart to the browser's `BarcodeDetector` or the ZXing-JS library. `pubspec.yaml` declares `platforms: web:`; nothing here works on mobile or desktop.

## Commands

```bash
flutter pub get
dart format .                       # CI gates on --set-exit-if-changed
flutter analyze --fatal-infos       # currently clean at this level
flutter test                        # 225 tests, VM only
flutter test --coverage             # CI enforces an 80% line floor
flutter test test/core/camera_selector_test.dart          # single file
flutter test --plain-name 'rank prefers the ultra-wide'   # single test

cd example && flutter run -d chrome  # runnable demo
cd example && flutter build web      # the only thing that compiles the interop layer
```

### CI

`.github/workflows/ci.yml` is the only workflow, and its two halves never run together.

**On a pull request** (and on manual dispatch), three jobs run in parallel: format + analyze + test with coverage + `pub publish --dry-run`; the same suite on the minimum supported SDK (Flutter 3.41.4); and a web build of `example/`. They re-run on every push to the PR, so what merges is what was verified.

**On a push to `main`** — i.e. when a PR lands — only the `publish` job runs. It compares `version:` in `pubspec.yaml` against the pub.dev API and does nothing unless that version is new, so ordinary merges cost one short job. When it *is* new it checks the CHANGELOG, re-runs analyze and the tests at the merge commit, publishes, then creates the `v<version>` tag and a GitHub release as a *record*. That tag is pushed with `GITHUB_TOKEN`, which by design does not start another workflow run.

`publish` deliberately has no `needs:` on the three PR jobs — they are skipped on a push, and depending on a skipped job would skip `publish` too. **Branch protection on `main` is what makes the PR gates binding**; the analyze and test steps inside `publish` are the second line of defence.

To cut a release: bump `version:` in `pubspec.yaml`, add a matching entry at the **top** of `CHANGELOG.md` (the job refuses to publish without one), and merge to `main`. Do not create tags by hand.

## Architecture

Five layers. A change to scanning behaviour usually touches the top two only.

1. **Widget** (`lib/src/widgets/omni_web_scanner.dart`) — the public surface. Owns nothing but presentation and the controller's lifetime.
2. **Controller** (`lib/src/controllers/`) — camera choice, session lifecycle, the decode→validation pipeline. Holds no `BuildContext` and imports nothing browser-specific.
3. **Core logic** (`lib/src/core/`) — pure, deterministic, no I/O: `CameraSelector`, `DetectionStabilizer`, `BarcodeValidator`, `MimeSniffer`. This is where the interesting decisions live and where most tests point.
4. **Platform seam** (`lib/src/platform/scanner_platform.dart`) — the `ScannerPlatform` interface plus a conditional import: `scanner_platform_web.dart` on web, `scanner_platform_stub.dart` everywhere else.
5. **`assets/js/scanner.js`** — the browser code, shipped as a Flutter asset and injected lazily on first use.

### The platform seam is load-bearing

`dart:js_interop`, `package:web` and `dart:ui_web` do not compile on the Dart VM. Without this seam `flutter test` could not even load the package. Two consequences:

- **`flutter test` never exercises `scanner_platform_web.dart`.** Tests inject `FakeScannerPlatform` (`test/fakes/`), either as a constructor argument or through `ScannerPlatformResolver.instance`. The web implementation is only verified by `cd example && flutter build web`, which CI runs.
- **Adding a JS function requires two edits**: an entry in the `window.omniScanner` object inside `assets/js/scanner.js` *and* a matching `external` binding in `lib/src/platform/scanner_interop.dart`.

Every interop call exchanges **JSON strings**, not structured objects. That keeps `scanner_interop.dart` a flat list of primitives and pushes all field mapping into `scanner_codec.dart`, which is testable without a browser — so parsing changes belong there, not in the interop file.

The script is injected on first `initialize()`, keyed by an element id so it is idempotent, with the in-flight injection shared so concurrent callers cannot append duplicate `<script>` tags. ZXing-JS itself is *not* bundled — the host app loads it from a CDN in `web/index.html`, unless it opts into `ScanEngine.native`.

### Camera selection (`lib/src/core/camera_selector.dart`)

The most intricate logic in the package and the source of most of the CHANGELOG history. It exists because browsers expose each lens of a multi-camera phone as a separate `videoinput` device, and picking the wrong lens breaks close-range focus.

`CameraSelector.rank` blends three signal tiers, in descending order of trust:

1. **Measured capabilities** — `focusDistance`, frame size, focus modes, read from a live `MediaStreamTrack`. Dominates when present.
2. **Reported facing mode** from `InputDeviceInfo.getCapabilities()`. Authoritative but Chromium-only.
3. **Label keywords**, in seven languages. A last resort: labels are localised, vendor-specific and empty before permission is granted.

Higher score wins (the inverse of 1.x). `rank` never returns fewer cameras than it was given — unsuitable ones sink instead of being dropped, because a laptop whose only camera is front-facing must still scan. There are no platform-specific branches; `ScanDistance` states the caller's intent instead.

`ScannerController._probeCandidates` opens the top candidates briefly to measure them, then re-ranks. Probing is best-effort: any failure is absorbed, since it must never stop the scanner from starting.

The scoring cannot be validated from code alone — changes here need real-device verification across iOS and Android browsers. `CameraCandidate.reasons` carries a human-readable score breakdown for exactly that.

### Detection pipeline (`lib/src/core/detection_stabilizer.dart`)

A live camera feeds the decoder tens of frames per second, and engines will happily return a structurally valid but wrong payload from a half-covered 1D symbol. Every raw decode goes through `DetectionStabilizer.offer`, which validates, counts confirmations within a window, and applies a per-value cooldown before `onDetect` fires. It owns no timers and reads time through an injectable `clock`, so it is fully testable without waiting.

`ScannerController.start()` resets the stabiliser, so a code read before a restart cannot suppress the same code read after it.

### Lifecycle

`ScannerState` is a sealed hierarchy (`Idle`/`Initializing`/`Ready`/`Failed`), so the widget's `switch` is exhaustive. `ScannerController.start()` is guarded by a generation counter: a start superseded by a newer one abandons its work and stops any session it had already opened, rather than leaking the camera track.

The preview stays mounted in every state — unmounting the platform view would destroy the container the interop layer is waiting on.

## Conventions

- **Comments explain *why*, never *what*.** The existing comments carry the browser quirks and hardware trade-offs that justify each decision; match that.
- **Tests are behavioural and named as sentences.** Fakes over mocks — the interesting behaviour is the *sequence* of interop calls. New behaviour needs a test; the 80% coverage floor is enforced in CI.
- **No `print`.** The verbose `[JS]` logging lives in `scanner.js`, where a browser console on someone else's phone is the only instrument available.
- **User-facing copy goes in `lib/src/l10n/scanner_localizations.dart`**, never inline in a widget. Every `ScannerFailureKind` needs copy in all three bundled languages, and a test asserts they are distinct.
- **New failure modes get a `ScannerFailureKind`**, not a free-form string. Callers branch on the kind, and `isRetryable` decides whether a retry button appears.
- **Public API is only what `lib/omni_qrcode_barcode_web_reader.dart` exports.** Everything under `src/` is private to consumers, so moving files is non-breaking; changing an export is not.

## Consumer setup

```html
<!-- web/index.html, inside <head> — not needed with ScanEngine.native -->
<script src="https://unpkg.com/@zxing/library@latest/umd/index.min.js"></script>
```

```dart
OmniWebScanner(
  onDetect: (result) => print('${result.format.name}: ${result.value}'),
  onError: (failure) => print(failure.kind.name),
)
```

Camera access requires a secure context (HTTPS or `localhost`); a LAN IP surfaces as `ScannerFailureKind.insecureContext`.
