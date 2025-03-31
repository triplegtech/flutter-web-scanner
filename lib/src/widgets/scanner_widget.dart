// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:developer';
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util; // For promiseToFuture
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/barcode_result.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/barcode_overlay_widget.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/qr_code_overlay_widget.dart';

import '../../js_interop.dart' as interop;

// Export the result model

/// A widget to display a camera stream and scan for barcodes/QR codes on Flutter Web.=-
class ScannerWidget extends StatefulWidget {
  /// Called when a barcode or QR code is successfully detected.
  final ValueChanged<BarcodeResult> onDetect;

  /// Called when an error occurs during initialization or scanning.
  final ValueChanged<String>? onError;

  /// Placeholder widget to show while the camera is initializing.
  final Widget? placeholder;

  /// Width of the scanner view. Defaults to match parent constraints.
  final double? width;

  /// Height of the scanner view. Defaults to match parent constraints.
  final double? height;

  /// Controls how the video stream is scaled to fit the view.
  /// Note: The actual video rendering is handled by the browser's <video> element
  /// and its 'object-fit' style (set to 'cover' in JS). This BoxFit
  /// might have limited effect on the internal video scaling but controls the container.
  final BoxFit fit;
  final String? deviceId;
  final ScanMode scanMode;

  const ScannerWidget({
    super.key,
    required this.onDetect,
    this.onError,
    this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.deviceId,
    required this.scanMode,
  });

  @override
  State<ScannerWidget> createState() => _ScannerWidgetState();
}

class _ScannerWidgetState extends State<ScannerWidget> {
  final String _viewId =
      'web_barcode_scanner_${DateTime.now().microsecondsSinceEpoch}';

  late final String _videoContainerId = 'container_$_viewId';

  bool _isInitializing = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isDisposed = false;

  Timer? _debounceTimer;
  String? _lastDetectedValue;

  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _currentDeviceId = widget.deviceId;
    ui.platformViewRegistry.registerViewFactory(
      _viewId,
      (int viewId) => html.DivElement()
        ..id = _videoContainerId
        ..style.width = '100%'
        ..style.height = '100%',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _startCamera();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ScannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deviceId != oldWidget.deviceId && !_isDisposed) {
      if (kDebugMode) {
        log("WebBarcodeScanner: deviceId changed, restarting camera.");
      }
      _currentDeviceId = widget.deviceId;
      _stopCameraResources().then((_) {
        if (!_isDisposed) {
          _startCamera();
        }
      });
    }
  }

  Future<void> _startCamera() async {
    if (_isDisposed) return;

    setState(() {
      _isInitializing = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      await js_util.promiseToFuture<void>(interop.startCamera(
        _videoContainerId,
        _viewId,
        _currentDeviceId,
        allowInterop(_handleDetection),
        allowInterop(_handleError),
      ));
      if (!_isDisposed) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (!_isDisposed) {
        _handleError("Failed to initialize camera: ${e.toString()}");
      }
    }
  }

  void _handleDetection(String value, String format) {
    if (_isDisposed) return;

    if (value == _lastDetectedValue && _debounceTimer?.isActive == true) {
      return;
    }
    _lastDetectedValue = value;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      _lastDetectedValue = null;
    });

    widget.onDetect(BarcodeResult(value: value, format: format));
  }

  void _handleError(String error) {
    if (_isDisposed) return;

    log("WebBarcodeScanner Error: $error");
    setState(() {
      _isInitializing = false;
      _hasError = true;
      _errorMessage = error;
    });
    widget.onError?.call(error);

    _stopCameraResources();
  }

  Future<void> _stopCameraResources() async {
    try {
      await js_util.promiseToFuture<void>(interop.stopCamera(_viewId));
    } catch (e) {
      log("Error stopping camera via JS: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    _stopCameraResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          HtmlElementView(viewType: _viewId),
          if (!_isInitializing) ...[
            if (widget.scanMode == ScanMode.Barcode) BarcodeOverlayWidget(),
            if (widget.scanMode == ScanMode.QrCode) QrCodeOverlayWidget(),
          ],
          if (_isInitializing && widget.placeholder != null)
            widget.placeholder!,
          if (_isInitializing && widget.placeholder == null)
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(
                  Theme.of(context).textTheme.bodySmall?.color),
            ),
          if (_hasError)
            Container(
              color: Colors.black.withOpacity(0.7),
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error: $_errorMessage',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
