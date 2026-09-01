# Security Policy

## Supported versions

Only the latest release receives fixes. The package is small and has a single
maintainer; backporting to older tags is not realistic, and upgrading is
normally a version bump.

| Version | Supported |
|---|---|
| 1.0.x | ✅ |
| Anything under `omni_qrcode_barcode_web_reader` | ❌ — the private predecessor, no longer maintained |

## Reporting a vulnerability

**Do not open a public issue.**

Use GitHub's private reporting instead:

👉 **[Report a vulnerability](https://github.com/triplegtech/flutter-web-scanner/security/advisories/new)**

That opens a private thread visible only to the maintainers, and it is the
channel to use even if you are unsure whether what you found counts.

Please include:

* what an attacker can do, not just what is wrong;
* the browser and version, since almost everything here is browser-dependent;
* a reproduction — a minimal Flutter Web page is ideal, a description of the
  steps is fine;
* the package version or commit.

**What to expect:** an acknowledgement within a week and an assessment within
two. If the report is confirmed, the fix ships in the next release and the
advisory is published crediting you, unless you would rather not be named. If
it is not a vulnerability, you will get an explanation of why rather than
silence.

Please give a reasonable window to ship a fix before disclosing publicly.

## Scope

This is a browser-side Flutter package. It has no server, no account and no
network calls of its own, which rules out most vulnerability classes — but a
few things are genuinely in scope:

* **Injected script handling.** The package writes `assets/js/scanner.js` into
  the host page at runtime. Anything that lets a third party influence *what*
  gets injected, or that lets the injected script be shadowed or replaced, is a
  real finding.
* **The interop boundary.** Every call between Dart and JavaScript exchanges
  JSON strings. A decoded barcode is attacker-controlled data — it is whatever
  was printed on the paper someone pointed a camera at. Anything that lets a
  crafted payload escape being data and become code, or corrupt the parsing in
  `scanner_codec.dart`, is in scope.
* **Camera and stream lifecycle.** A path that leaves a `MediaStreamTrack` live
  after the scanner stops or is disposed leaves the camera on without the user
  knowing. Treat that as a security issue, not a resource leak.
* **Leaking scanned values.** Scanned codes are frequently personal or
  medical data. Anything that puts them somewhere the host app did not ask for
  — the console outside debug mode, the DOM, storage — is in scope.

### Out of scope

* **Camera permission prompts and secure-context enforcement.** Those are the
  browser's, and the package cannot weaken them. A LAN IP being rejected as
  `insecureContext` is the browser doing its job.
* **The host application's own handling of scanned values.** Once `onDetect`
  hands over a `BarcodeResult`, what happens to it is the app's responsibility.
* **Misreads.** A wrong decode is a correctness bug — please report it as an
  issue. `ScanValidation` (check digits, confirmation streaks, format filters)
  reduces them but is not a security boundary, and no configuration makes a
  scanned barcode trustworthy input.
* **ZXing-JS itself.** Report vulnerabilities in the decoder to
  [@zxing/library](https://github.com/zxing-js/library). See the note below for
  the part that *is* yours to control.

## A note on loading ZXing

Unless you use `ScanEngine.native`, the host app loads the decoder from a CDN,
and the README shows the quickest version of that:

```html
<script src="https://unpkg.com/@zxing/library@latest/umd/index.min.js"></script>
```

`@latest` means the page executes whatever that URL serves on the day it loads
— convenient for trying the package out, and a third-party dependency you do
not control for anything real. In production, pin an exact version and add a
Subresource Integrity hash so the browser refuses a script that has changed:

```html
<script
  src="https://cdn.jsdelivr.net/npm/@zxing/library@0.21.3/umd/index.min.js"
  integrity="sha384-…"
  crossorigin="anonymous"></script>
```

Better still, vendor the file into your own `web/` directory and serve it from
your origin, which removes the third party entirely. This is the host app's
decision, not the package's — the package only calls the global the script
defines.
