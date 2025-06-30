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




