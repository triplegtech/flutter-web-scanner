# Contributing

Thanks for taking the time. This package does one narrow thing — read barcodes
from a camera in a browser — and most of its complexity comes from the fact
that browsers disagree with each other about cameras. That shapes how changes
get reviewed, so it is worth reading this before opening a pull request.

## Before you write code

**Open an issue first for anything that changes behaviour.** Bug reports are
always welcome as-is, but a feature or a scoring change is much cheaper to
discuss than to review — especially in `lib/src/core/camera_selector.dart`,
where the "obvious" improvement often turns out to break a specific phone.

Small, self-evident fixes (a typo, a broken link, a wrong doc comment) can go
straight to a PR.

## Setting up

```bash
flutter pub get
flutter test                          # 269 tests, all on the Dart VM
cd example && flutter run -d chrome   # the runnable demo
```

Requires Flutter **3.41.4 or newer** (Dart `^3.11.0`). That floor is a promise
the CI verifies on every PR, so do not use an API newer than it.

To test on a real phone, `cd example && ./run_device.sh`. The camera needs a
secure context, so the dev server's LAN address is rejected as
`insecureContext` — the script exposes the example through a Cloudflare Quick
Tunnel (`brew install cloudflared`) whose `https://…trycloudflare.com` URL is
not.

## The thing to understand first

`dart:js_interop`, `package:web` and `dart:ui_web` do not compile on the Dart
VM, so the package hides the browser behind a seam: `ScannerPlatform` plus a
conditional import that resolves to `scanner_platform_web.dart` in a browser
and `scanner_platform_stub.dart` everywhere else.

**This means `flutter test` never runs a single line of the web
implementation.** A green test suite tells you nothing about
`scanner_platform_web.dart`, `scanner_interop.dart` or `assets/js/scanner.js`.
The only automated check on that layer is that it compiles:

```bash
cd example && flutter build web
```

CI runs that on every PR. Anything beyond "it compiles" has to be verified by
hand in a browser.

## Layout

| Layer | Where | What belongs there |
|---|---|---|
| Widget | `lib/src/widgets/web_scanner.dart` | Presentation and the controller's lifetime. Nothing else. |
| Controller | `lib/src/controllers/` | Camera choice, session lifecycle, the decode→validation pipeline. No `BuildContext`, nothing browser-specific. |
| Core logic | `lib/src/core/` | Pure and deterministic, no I/O. Most tests point here. |
| Platform seam | `lib/src/platform/` | The interface, the conditional import, the JS bindings and the JSON codec. |
| Browser code | `assets/js/scanner.js` | Shipped as a Flutter asset, injected on first use. |

Two rules that are easy to trip over:

* **Adding a JS function takes two edits** — an entry in the
  `window.flutterWebScanner` object in `assets/js/scanner.js`, *and* a matching
  `external` binding in `lib/src/platform/scanner_interop.dart`. Miss one and
  the failure appears at runtime in a browser, not at compile time.
* **Every interop call exchanges JSON strings**, never structured objects. That
  keeps `scanner_interop.dart` a flat list of primitives and pushes all field
  mapping into `scanner_codec.dart` — which is testable without a browser, so
  parsing changes belong there.

## Changing camera selection

`CameraSelector.rank` is the most intricate code in the package and the source
of most of the changelog. Browsers expose every lens of a multi-camera phone as
a separate `videoinput` device, and picking the wrong lens breaks close-range
focus — a scanner that will not read a barcode held 10 cm away is usually a
lens problem, not a decoder problem.

It blends three signal tiers, in descending order of trust:

1. **Measured capabilities** (`focusDistance`, frame size, focus modes) read
   from a live `MediaStreamTrack`. Dominates when present.
2. **Reported facing mode** from `InputDeviceInfo.getCapabilities()`.
   Authoritative, but Chromium-only.
3. **Label keywords**, in seven languages. A last resort — labels are
   localised, vendor-specific, and empty before permission is granted.

If you change the scoring:

* **`rank` must never return fewer cameras than it was given.** Unsuitable ones
  sink in the ordering; they are not dropped. A laptop whose only camera faces
  the user still has to scan.
* **No platform-specific branches.** `ScanDistance` states the caller's intent;
  the selector reacts to capabilities, not to user-agent sniffing.
* **Verify on real hardware, on both iOS and Android**, and say so in the PR.
  This scoring cannot be validated from code alone.
  `CameraCandidate.reasons` carries a human-readable breakdown of every score
  for exactly this purpose — paste it into the PR.

## Tests

New behaviour needs a test. CI enforces an **80% line-coverage floor**.

* **Behavioural, named as sentences.** `test('rank prefers the ultra-wide when
  scanning near', ...)`, not `test('rank1', ...)`.
* **Fakes over mocks.** Inject `FakeScannerPlatform` (`test/fakes/`) either as a
  constructor argument or through `ScannerPlatformResolver.instance`. The
  interesting thing to assert is usually the *sequence* of interop calls.
* **No waiting on real time.** `DetectionStabilizer` owns no timers and reads
  the clock through an injectable `clock`; keep it that way, and use
  `fake_async` where you need to move time.

```bash
flutter test                                              # everything
flutter test test/core/camera_selector_test.dart          # one file
flutter test --plain-name 'rank prefers the ultra-wide'   # one test
flutter test --coverage                                   # what CI measures
```

## Conventions

* **Comments explain *why*, never *what*.** The existing ones carry the browser
  quirks and hardware trade-offs that justify each decision. A comment that
  restates the code will be asked about in review; one that records why Safari
  needed something will not.
* **No `print` in Dart.** The verbose logging lives in `scanner.js`, where a
  browser console on someone else's phone is the only instrument available.
  Users switch it on with `window.flutterWebScanner.debug = true`.
* **New failure modes get a `ScannerFailureKind`**, not a free-form string.
  Callers branch on the kind, and `isRetryable` decides whether the built-in UI
  offers a retry.
* **User-facing copy goes in `lib/src/l10n/scanner_localizations.dart`**, never
  inline in a widget, and every `ScannerFailureKind` needs copy in **all three**
  bundled languages (English, Portuguese, Spanish). A test asserts they are
  distinct.
* **The public API is exactly what `lib/flutter_web_scanner.dart` exports.**
  Everything under `src/` is private to consumers, so moving a file is not a
  breaking change — changing an export is.
* **Run `dart format .` before committing.** CI reports formatting as a warning
  rather than a failure, because `dart format` output changes between Dart
  releases and a job tracking stable would flag files formatted on the SDK
  floor through no fault of the author.

## Opening the pull request

1. **Branch off `main`.** `fix/`, `feat/` or `docs/` prefixes read well; nothing
   enforces them.
2. **Keep it to one concern.** A rename bundled with a behaviour change is much
   harder to review, and much harder to revert.
3. **Run the gates locally** — `dart format .`, `flutter analyze --fatal-infos`,
   `flutter test`, and `cd example && flutter build web` if you touched
   anything under `lib/src/platform/` or `assets/`.
4. **Fill in the PR template.** The device/browser question is not a formality:
   for anything touching the camera it is the only evidence that exists.
5. **Do not bump the version.** Releases are cut separately (see below), and a
   version bump in a feature PR will collide with the next one.

Every PR runs three jobs: analyze + tests with the coverage floor + a
`pub publish --dry-run` layout check; the same suite on the minimum supported
SDK; and a web build of the example. They re-run on every push, so what merges
is what was verified.

Review aims to be quick and specific. Expect questions about *why*, especially
on the camera and validation paths — a change that is correct but unexplained
is one nobody can safely modify later.

## Releasing

Maintainers only, one branch per version:

1. Branch off `main` — `release/1.1.0` by convention.
2. Bump `version:` in `pubspec.yaml` and add the matching `## 1.1.0` section at
   the **top** of `CHANGELOG.md`. That section becomes the body of the GitHub
   release, so write it for whoever will read the release page.
3. Open a PR, let the gates run, merge.

CI then re-runs analyze and the tests at the merge commit, tags it `v1.1.0` and
creates the GitHub release from the CHANGELOG section. Merges that change no
version release nothing. **Do not create tags by hand.**

The version branch stays in the repository after the merge.

## Reporting bugs and asking for features

See the [issue templates](https://github.com/triplegtech/flutter-web-scanner/issues/new/choose).
For anything camera-related, the browser, its version, the OS and the device
model are the difference between a fixable report and an unreproducible one.

Security problems do **not** go in an issue — see [SECURITY.md](SECURITY.md).

## Code of conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Licence

By contributing you agree that your contributions are licensed under the
[MIT Licence](LICENSE), the same terms that cover the rest of the package.
