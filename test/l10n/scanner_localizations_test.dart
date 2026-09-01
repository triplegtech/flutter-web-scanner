import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_scanner/flutter_web_scanner.dart';

void main() {
  const bundled = <String, ScannerLocalizations>{
    'en': ScannerLocalizations.en,
    'pt': ScannerLocalizations.ptBr,
    'es': ScannerLocalizations.es,
  };

  group('forLocale', () {
    test('matches on language code, ignoring the country', () {
      // A pt-PT app gets the Portuguese copy; falling through to English
      // because the country differs would be a worse outcome.
      expect(
        ScannerLocalizations.forLocale(const Locale('pt', 'PT')),
        same(ScannerLocalizations.ptBr),
      );
      expect(
        ScannerLocalizations.forLocale(const Locale('es', 'AR')),
        same(ScannerLocalizations.es),
      );
    });

    test('is case-insensitive about the language code', () {
      expect(
        ScannerLocalizations.forLocale(const Locale('PT')),
        same(ScannerLocalizations.ptBr),
      );
    });

    test('falls back to English for an unbundled language', () {
      expect(
        ScannerLocalizations.forLocale(const Locale('de')),
        same(ScannerLocalizations.en),
      );
    });

    test('falls back to English when the app declares no locale', () {
      expect(
        ScannerLocalizations.forLocale(null),
        same(ScannerLocalizations.en),
      );
    });
  });

  group('messageFor', () {
    for (final entry in bundled.entries) {
      test(
        '${entry.key} has distinct, non-empty copy for every failure kind',
        () {
          final messages = <String>[];
          for (final kind in ScannerFailureKind.values) {
            final message = entry.value.messageFor(kind);
            expect(message.trim(), isNotEmpty, reason: '${kind.name} is blank');
            messages.add(message);
          }

          // Duplicated copy means two different problems read identically to the
          // user, which is the failure mode a copy-paste translation introduces.
          expect(messages.toSet(), hasLength(ScannerFailureKind.values.length));
        },
      );

      test('${entry.key} translates the retry and loading labels', () {
        expect(entry.value.retry.trim(), isNotEmpty);
        expect(entry.value.initializing.trim(), isNotEmpty);
      });
    }

    test('translations differ from English where a translation exists', () {
      // Guards against a new string being added to `en` and copied verbatim
      // into the other bundles.
      for (final kind in ScannerFailureKind.values) {
        expect(
          ScannerLocalizations.ptBr.messageFor(kind),
          isNot(ScannerLocalizations.en.messageFor(kind)),
          reason: '${kind.name} is untranslated in pt',
        );
        expect(
          ScannerLocalizations.es.messageFor(kind),
          isNot(ScannerLocalizations.en.messageFor(kind)),
          reason: '${kind.name} is untranslated in es',
        );
      }
    });
  });
}
