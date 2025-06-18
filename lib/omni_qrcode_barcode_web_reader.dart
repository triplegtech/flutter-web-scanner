export 'src/pages/scanner_page.dart';
export 'src/enums/overlay_enum.dart';
export 'src/services/scan_service.dart';

import 'dart:html' as html;

import 'package:flutter/services.dart';

Future<void> injectOmniWebReaderWebDependencies() async {
  const String interopScriptId = 'omni-web-scanner-interop-script';

  if (html.document.getElementById(interopScriptId) != null) return;

  const assetPath =
      'packages/omni_qrcode_barcode_web_reader/assets/js/scanner.js';
  final jsCode = await rootBundle.loadString(assetPath, cache: false);

  final scriptElement = html.ScriptElement()
    ..id = interopScriptId
    ..type = 'text/javascript'
    ..innerHtml = jsCode;

  html.document.head?.append(scriptElement);
}
