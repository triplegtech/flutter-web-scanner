// ignore_for_file: unused_field

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omni_qrcode_barcode_web_reader/src/enums/overlay_enum.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/barcode_result.dart';
import 'package:omni_qrcode_barcode_web_reader/src/models/camera_model.dart';
import 'package:omni_qrcode_barcode_web_reader/src/services/camera_service.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/error_widget.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_widget.dart';

class OmniWebScanner extends StatefulWidget {
  final ValueChanged<BarcodeResult> onDetect;
  final ValueChanged<String>? onError;

  final Widget? placeholder;
  final double? height;
  final double? width;
  final BoxFit? fit;

  final ScanMode overlay;

  const OmniWebScanner({
    super.key,
    required this.onDetect,
    required this.onError,
    this.placeholder,
    this.height,
    this.width,
    this.fit,
    this.overlay = ScanMode.Barcode,
  });

  @override
  State<OmniWebScanner> createState() => _OmniWebScannerState();
}

class _OmniWebScannerState extends State<OmniWebScanner> {
  BarcodeResult? _latestResult;
  String _errorMessage = '';

  // State for camera selection
  List<CameraModel> _cameras = [];
  CameraModel? _selectedCamera;
  bool _isLoadingCameras = kIsWeb; // Start loading only on web
  bool _hasCameraPermission = true; // Assume true initially
  bool _showScanner = false; // Only show scanner after selection/confirmation

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadCameras();
    } else {
      setState(() {
        _isLoadingCameras = false;
        _errorMessage = "WebBarcodeScanner only works on Flutter Web.";
      });
    }
  }

  Future<void> _loadCameras() async {
    setState(() {
      _isLoadingCameras = true;
      _errorMessage = ''; // Clear previous errors
      _hasCameraPermission = true; // Reset permission assumption
    });
    try {
      final device = await getCameraDevice();
      if (mounted) {
        if (device == null) {
          setState(() {
            _errorMessage =
                "No cameras found or permission denied. Please ensure you've granted camera access to this site.";
            _hasCameraPermission = false;
          });
        }
        setState(() {
          _cameras = [device!];
          if (_cameras.isNotEmpty) {
            _selectedCamera = _cameras.first;

            _startScanner();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error loading cameras: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCameras = false;
        });
      }
    }
  }

  void _startScanner() {
    if (_selectedCamera != null || _cameras.isNotEmpty) {
      setState(() {
        _showScanner = true;
        _latestResult = null;
        _errorMessage = '';
      });
    } else if (!_hasCameraPermission) {
      setState(() {
        _errorMessage =
            "Cannot start scanner: Camera permission denied or no cameras found.";
      });
    } else {
      setState(() {
        _errorMessage =
            "Cannot start scanner: No camera selected or available.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      if (!_hasCameraPermission) {
        return CameraErrorWidget(
          error: _errorMessage.isNotEmpty
              ? _errorMessage
              : 'Permissão da câmera é necessária',
        );
      } else if (_selectedCamera == null &&
          !_hasCameraPermission &&
          !_isLoadingCameras) {
        return const CameraErrorWidget(error: 'Nenhuma câmera foi encontrada');
      } else if (_selectedCamera == null && _isLoadingCameras) {
        return Center(
          child: widget.placeholder ??
              SizedBox(
                child: CircularProgressIndicator(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
        );
      } else {
        return ScannerWidget(
          key: ValueKey(_selectedCamera?.deviceId),
          onDetect: widget.onDetect,
          onError: widget.onError,
          deviceId: _selectedCamera?.deviceId,
          fit: widget.fit ?? BoxFit.cover,
          height: widget.height,
          width: widget.width,
          placeholder: widget.placeholder,
          scanMode: widget.overlay,
        );
      }
    } else {
      return CameraErrorWidget(
        error: 'Scanner requires Flutter Web.',
      );
    }
  }
}
