<!--
Thanks for the contribution. Delete whatever does not apply — this is a
checklist, not a form to fill in exhaustively.
-->

## What this changes

<!-- And why. The "why" is what review will ask about first. -->

Fixes #

## How it was verified

<!--
`flutter test` runs entirely on the Dart VM, where the conditional import
resolves to the unsupported stub — so a green suite says nothing at all about
`scanner_platform_web.dart`, `scanner_interop.dart` or `assets/js/scanner.js`.
For anything touching those, or the camera, say what you actually ran it on.
-->

- [ ] `dart format .`
- [ ] `flutter analyze --fatal-infos`
- [ ] `flutter test` — new behaviour has a test
- [ ] `cd example && flutter build web` (required if this touches `lib/src/platform/` or `assets/`)

**Tested in a real browser on:** <!-- e.g. Safari 18 / iPhone 13, Chrome 131 / Galaxy S23 — or "not applicable" -->

## If this touches camera selection

<!--
`CameraSelector.rank` cannot be validated from code alone. Delete this section
if you did not touch `lib/src/core/camera_selector.dart` or the probing in
`ScannerController`.
-->

- [ ] Verified on real hardware, on **both** iOS and Android
- [ ] `rank` still never returns fewer cameras than it was given
- [ ] No platform- or user-agent-specific branches were added

<details>
<summary><code>CameraCandidate.reasons</code> from the devices tested</summary>

```
paste the score breakdown here
```

</details>

## Checklist

- [ ] Comments explain *why*, not *what*
- [ ] No `print` in Dart code
- [ ] A new failure mode is a `ScannerFailureKind`, not a free-form string
- [ ] New user-facing copy is in `scanner_localizations.dart`, in **all three** languages
- [ ] If the public API changed, `lib/flutter_web_scanner.dart` exports it
- [ ] **No version bump** — releases are cut separately, and a bump here will collide with the next one
