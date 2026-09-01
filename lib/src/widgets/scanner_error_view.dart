import 'package:flutter/material.dart';
import 'package:flutter_web_scanner/src/l10n/scanner_localizations.dart';
import 'package:flutter_web_scanner/src/models/scanner_failure.dart';

/// Default presentation for a [ScannerFailure].
class ScannerErrorView extends StatelessWidget {
  const ScannerErrorView({
    super.key,
    required this.failure,
    required this.localizations,
    this.onRetry,
    this.icon,
  });

  final ScannerFailure failure;
  final ScannerLocalizations localizations;

  /// Retry handler. The button appears only when this is provided *and* the
  /// failure is retryable — offering "try again" for a denied permission or a
  /// missing engine leads nowhere, since the retry fails identically.
  final VoidCallback? onRetry;

  final IconData? icon;

  bool get _showRetry => onRetry != null && failure.isRetryable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium;

    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon ?? _iconFor(failure.kind),
              size: 42,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.messageFor(failure.kind),
              textAlign: TextAlign.center,
              style: bodyStyle?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (_showRetry) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onRetry,
                child: Text(localizations.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(ScannerFailureKind kind) => switch (kind) {
    ScannerFailureKind.permissionDenied => Icons.no_photography_outlined,
    ScannerFailureKind.noCameraFound => Icons.videocam_off_outlined,
    ScannerFailureKind.cameraInUse => Icons.lock_outline,
    ScannerFailureKind.insecureContext => Icons.https_outlined,
    ScannerFailureKind.engineUnavailable => Icons.extension_off_outlined,
    ScannerFailureKind.unsupportedPlatform => Icons.devices_other_outlined,
    ScannerFailureKind.overconstrained ||
    ScannerFailureKind.startFailed ||
    ScannerFailureKind.unknown => Icons.error_outline,
  };
}
