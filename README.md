# Omni QR Code / Barcode Web Reader

[![pub version](https://img.shields.io/pub/v/omni_qrcode_barcode_web_reader.svg)](https://pub.dev/packages/omni_qrcode_barcode_web_reader) <!-- Replace with your actual package name if different -->
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Or your chosen license -->
![Flutter Platform](https://img.shields.io/badge/Platform-Web-blue)

A Flutter widget for **web applications** to scan QR codes and various barcode formats using the device's camera via JavaScript interoperability.

This package leverages the browser's `getUserMedia` API to access the camera and uses the [ZXing-JS library](https://github.com/zxing-js/library) for decoding barcodes and QR codes.

## Features

*   Access camera stream on Flutter Web.
*   Decode QR codes and common barcode formats (powered by ZXing-JS).
*   Callback on successful detection (`onDetect`).
*   Callback for errors (`onError`) like permission denial or camera issues.
*   Customizable overlay to guide the user:
    *   Dimmed background outside the scanning area.
    *   Clear scanning area (cutout).
    *   Selectable overlay shapes optimized for QR Codes or Barcodes (`ScanMode`).
*   Optional placeholder widget during camera initialization.

## Parameters

* onDetect: Callback function whenever the scan works;

    ```dart
    void Function(BarcodeResult result) {

    }
    ```
* onError: Callback function whenever the scan fails;
    ```dart
    void Function?(String? error) {

    }
    ```
* height: Scanner vertical size;
* width: Scanner horizontal size;
* placeholder: Widget shown while scanner is initializing;
* fit: Scanner boxfit property to adjust its content to given size
* scanMode: Scanner modes to switch custom overlay.
    ```dart
        ScanMode.Barcode
        ScanMode.QrCode
    ```


## Platform Support

*   ✅ **Flutter Web Only**
*   ✅ **Dart >= 3.6.0**

This package relies heavily on web-specific APIs (`navigator.mediaDevices`, `HtmlElementView`) and JavaScript interoperability, so it will **not** work on mobile or desktop platforms.

## Getting Started

### 1. Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  omni_qrcode_barcode_web_reader: ^latest # Check pub.dev for the latest version
  js: ^0.6.7 # Or latest JS interop package version
  get: ^4.7.2 # Or higher, check pub.dev for the latest stable version
```

### 2. Setup

Add the ZXing-JS library script tag inside the <head> section of your web/index.html. Using a CDN is the simplest way:

```html
<!-- web/index.html -->
<!DOCTYPE html>
<html>
<head>
  <!-- ... other head elements ... -->
  <title>My Scanner App</title>

  <!-- ADD ZXing-JS Library -->
  <script type="text/javascript" src="https://unpkg.com/@zxing/library@latest/umd/index.min.js"></script>

  <!-- ... other head elements ... -->
</head>
<body>
  <!-- Flutter app script will be here -->
  <script src="main.dart.js" type="application/javascript"></script>
</body>
</html>
```

> ⚠️ **Important**
 Its required to add this script to your application, otherwise it wont run properly.

### 3. Implementation

Before you run your flutter application you need to inject the package web dependencies using a spefic function:

```dart
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //DI Function
  await injectOmniWebReaderWebDependencies();
  runApp(const MyApp());
}
```
> This will insert all needed javascript code 
