import 'package:omni_qrcode_barcode_web_reader/src/models/scanner_failure.dart';
import 'package:omni_qrcode_barcode_web_reader/src/platform/scanner_platform.dart';

/// Lifecycle of a scanner instance.
///
/// Modelled as a sealed hierarchy so the widget's `switch` is exhaustive and
/// the compiler catches a forgotten branch. 1.x tracked this with four
/// independent booleans, whose combinations included unreachable states and
/// one genuinely wrong branch that could never be entered.
sealed class ScannerState {
  const ScannerState();
}

/// Created but not started.
final class ScannerIdle extends ScannerState {
  const ScannerIdle();
}

/// Enumerating cameras, probing capabilities, or opening the stream.
final class ScannerInitializing extends ScannerState {
  const ScannerInitializing();
}

/// Streaming and decoding.
final class ScannerReady extends ScannerState {
  const ScannerReady(this.session);

  final ScanSession session;
}

/// Stopped by a failure.
final class ScannerFailed extends ScannerState {
  const ScannerFailed(this.failure);

  final ScannerFailure failure;

  /// Whether offering the user a retry could plausibly help.
  bool get isRetryable => failure.isRetryable;
}
