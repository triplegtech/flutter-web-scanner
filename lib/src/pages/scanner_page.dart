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
  String _errorMessage = '';
  CameraModel? _selectedCamera;
  bool _isLoadingCameras = kIsWeb;
  bool _hasCameraPermission = true;
  bool _showScanner = false;

  Future<void> _loadCameras() async {
    setState(() {
      _isLoadingCameras = true;
      _errorMessage = '';
      _hasCameraPermission = true;
    });
    try {
      final device = await getCameraDevice();
      if (mounted) {
        if (device == null) {
          setState(() {
            _errorMessage =
                "Nenhuma câmera encontrada ou permissão negada. Por favor, certifique-se de que você concedeu acesso à câmera para este site.";
            _hasCameraPermission = false;
          });
        }
        setState(() {
          _selectedCamera = device;
          _startScanner();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error ao carregar câmeras: $e";
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
    if (_selectedCamera != null) {
      setState(() {
        _showScanner = true;
        _errorMessage = '';
      });
    } else if (!_hasCameraPermission) {
      setState(() {
        _errorMessage =
            "Permissão de câmera negada ou nenhuma câmera encontrada.";
      });
    } else {
      setState(() {
        _errorMessage = "Nenhuma câmera selecionada ou disponível";
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadCameras();
    } else {
      setState(() {
        _isLoadingCameras = false;
        _errorMessage = "Omni web scanner only works on Flutter Web.";
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
      }
      if (_showScanner || (!_showScanner && _isLoadingCameras)) {
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
      } else {
        return CameraErrorWidget(
          error: 'Erro ao inicializar scanner.',
        );
      }
    } else {
      return CameraErrorWidget(
        error: _errorMessage.isNotEmpty
            ? _errorMessage
            : 'Scanner requires Flutter Web.',
      );
    }
  }
}
