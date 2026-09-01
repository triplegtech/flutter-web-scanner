import 'dart:ui' show Locale;

import 'package:flutter_web_scanner/src/models/scanner_failure.dart';

/// User-facing copy for the scanner's error and loading states.
///
/// 1.x hardcoded Brazilian Portuguese strings across three widgets, and the
/// only language check compared `navigator.language` against `'pt_BR'` — a
/// value browsers never produce, since the tag is `pt-BR` — so it was dead code
/// that always chose Portuguese. This resolves language from the app's own
/// [Locale] instead, and lets callers substitute their own copy wholesale.
class ScannerLocalizations {
  const ScannerLocalizations({
    required this.permissionDenied,
    required this.noCameraFound,
    required this.cameraInUse,
    required this.overconstrained,
    required this.engineUnavailable,
    required this.insecureContext,
    required this.unsupportedPlatform,
    required this.startFailed,
    required this.unknownError,
    required this.retry,
    required this.initializing,
  });

  final String permissionDenied;
  final String noCameraFound;
  final String cameraInUse;
  final String overconstrained;
  final String engineUnavailable;
  final String insecureContext;
  final String unsupportedPlatform;
  final String startFailed;
  final String unknownError;
  final String retry;
  final String initializing;

  static const ScannerLocalizations en = ScannerLocalizations(
    permissionDenied:
        'Camera access is required to scan. Please allow camera '
        'access for this site in your browser settings.',
    noCameraFound: 'No camera was found on this device.',
    cameraInUse:
        'The camera is being used by another app or tab. Close it and '
        'try again.',
    overconstrained: 'This camera does not support the requested settings.',
    engineUnavailable:
        'The barcode scanning engine is unavailable in this '
        'browser.',
    insecureContext: 'The camera only works over HTTPS or on localhost.',
    unsupportedPlatform: 'The scanner is only supported on Flutter Web.',
    startFailed: 'The camera could not be started.',
    unknownError: 'Something went wrong while starting the camera.',
    retry: 'Try again',
    initializing: 'Starting camera...',
  );

  static const ScannerLocalizations ptBr = ScannerLocalizations(
    permissionDenied:
        'É necessário permitir o acesso à câmera para escanear. '
        'Conceda a permissão para este site nas configurações do navegador.',
    noCameraFound: 'Nenhuma câmera foi encontrada neste dispositivo.',
    cameraInUse:
        'A câmera está sendo usada por outro aplicativo ou aba. '
        'Feche-o e tente novamente.',
    overconstrained: 'Esta câmera não suporta as configurações solicitadas.',
    engineUnavailable:
        'O motor de leitura de códigos não está disponível '
        'neste navegador.',
    insecureContext: 'A câmera só funciona em HTTPS ou em localhost.',
    unsupportedPlatform: 'O scanner só é suportado no Flutter Web.',
    startFailed: 'Não foi possível iniciar a câmera.',
    unknownError: 'Ocorreu um erro ao iniciar a câmera.',
    retry: 'Tentar novamente',
    initializing: 'Iniciando câmera...',
  );

  static const ScannerLocalizations es = ScannerLocalizations(
    permissionDenied:
        'Se requiere acceso a la cámara para escanear. Permite '
        'el acceso a este sitio en la configuración del navegador.',
    noCameraFound: 'No se encontró ninguna cámara en este dispositivo.',
    cameraInUse:
        'Otra aplicación o pestaña está usando la cámara. Ciérrala e '
        'inténtalo de nuevo.',
    overconstrained: 'Esta cámara no admite la configuración solicitada.',
    engineUnavailable:
        'El motor de lectura de códigos no está disponible en '
        'este navegador.',
    insecureContext: 'La cámara solo funciona con HTTPS o en localhost.',
    unsupportedPlatform: 'El escáner solo es compatible con Flutter Web.',
    startFailed: 'No se pudo iniciar la cámara.',
    unknownError: 'Se produjo un error al iniciar la cámara.',
    retry: 'Reintentar',
    initializing: 'Iniciando cámara...',
  );

  /// Picks the closest bundled translation for [locale], defaulting to [en].
  ///
  /// Matching is on language code alone: a `pt-PT` app gets the Portuguese
  /// copy, which is far better than falling through to English.
  static ScannerLocalizations forLocale(Locale? locale) =>
      switch (locale?.languageCode.toLowerCase()) {
        'pt' => ptBr,
        'es' => es,
        _ => en,
      };

  /// Copy to display for [kind].
  String messageFor(ScannerFailureKind kind) => switch (kind) {
    ScannerFailureKind.permissionDenied => permissionDenied,
    ScannerFailureKind.noCameraFound => noCameraFound,
    ScannerFailureKind.cameraInUse => cameraInUse,
    ScannerFailureKind.overconstrained => overconstrained,
    ScannerFailureKind.engineUnavailable => engineUnavailable,
    ScannerFailureKind.insecureContext => insecureContext,
    ScannerFailureKind.unsupportedPlatform => unsupportedPlatform,
    ScannerFailureKind.startFailed => startFailed,
    ScannerFailureKind.unknown => unknownError,
  };
}
