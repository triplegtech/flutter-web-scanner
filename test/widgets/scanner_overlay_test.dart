import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_overlay_shape.dart';

void main() {
  // Fixed so the window the overlay carves out can be named in coordinates.
  const hostWidth = 300.0;
  const hostHeight = 400.0;

  Widget host(
    ScannerOverlayStyle style, {
    double width = hostWidth,
    double height = hostHeight,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ScannerOverlay(style: style),
            ),
          ),
        ),
      );

  group('dimming', () {
    testWidgets('paints without an offscreen layer', (tester) async {
      // saveLayer makes CanvasKit allocate a viewport-sized texture, render
      // into it and composite it back. The overlay used to ask for one on
      // every paint, to punch the window out with BlendMode.dstOut.
      await tester.pumpWidget(host(const ScannerOverlayStyle()));

      expect(
        find.byType(ScannerOverlay),
        paintsExactlyCountTimes(#saveLayer, 0),
      );
    });

    testWidgets('covers the preview except the framing window', (tester) async {
      await tester.pumpWidget(
        host(const ScannerOverlayStyle(showScanLine: false)),
      );

      expect(
        find.byType(ScannerOverlay),
        paints
          ..path(
            includes: const <Offset>[
              Offset(5, 5),
              Offset(hostWidth / 2, hostHeight - 10),
            ],
            excludes: const <Offset>[Offset(hostWidth / 2, 180)],
          ),
      );
    });

    testWidgets('keeps the window inside a preview shorter than the cut-out',
        (tester) async {
      // cutOutBottomOffset lifts the window to leave room for instructions
      // below it. With a cut-out taller than the preview that lift used to
      // carry the window off the top edge, clipping the upper brackets away.
      await tester.pumpWidget(
        host(
          const ScannerOverlayStyle(showScanLine: false),
          height: 250,
        ),
      );

      expect(
        find.byType(ScannerOverlay),
        paints
          ..path(
            includes: const <Offset>[
              Offset(hostWidth / 2, 1),
              Offset(hostWidth / 2, 249),
            ],
            excludes: const <Offset>[Offset(hostWidth / 2, 120)],
          ),
      );
    });
  });

  group('sweep line', () {
    Finder lineIn(Finder overlay) => find.descendant(
          of: overlay,
          matching: find.byType(RepaintBoundary),
        );

    testWidgets('travels down the framing window', (tester) async {
      await tester.pumpWidget(host(const ScannerOverlayStyle()));

      final line = lineIn(find.byType(ScannerOverlay));
      final start = tester.getTopLeft(line).dy;
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.getTopLeft(line).dy, greaterThan(start));
    });

    testWidgets('reaches both edges of the window and neither passes them',
        (tester) async {
      // 1.x swept -0.075 → 0.80 of the cut-out's height, so the line began
      // above the frame and stopped a fifth short of its bottom.
      const style = ScannerOverlayStyle();
      await tester.pumpWidget(host(style));

      final overlay = tester.getRect(find.byType(ScannerOverlay));
      final window = ScannerOverlayShape(
        cutOutWidth: hostWidth * style.cutOutWidthFactor,
        cutOutHeight: style.cutOutHeight,
        cutOutBottomOffset: style.cutOutBottomOffset,
        borderWidth: style.borderWidth,
        borderLength: style.borderLength,
        borderRadius: style.borderRadius,
      ).windowFor(Offset.zero & overlay.size).outerRect.shift(overlay.topLeft);

      final line = lineIn(find.byType(ScannerOverlay));
      var highest = double.infinity;
      var lowest = double.negativeInfinity;
      // A full sweep, sampled densely enough to catch either extreme.
      for (var frame = 0; frame < 45; frame++) {
        final rect = tester.getRect(line);
        highest = math.min(highest, rect.top);
        lowest = math.max(lowest, rect.bottom);
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(highest, greaterThanOrEqualTo(window.top - 0.01));
      expect(lowest, lessThanOrEqualTo(window.bottom + 0.01));
      expect(highest, closeTo(window.top, 0.5));
      expect(lowest, closeTo(window.bottom, 0.5));
    });

    testWidgets('is moved by a transform, not repainted', (tester) async {
      // The line is rasterised once and thereafter only translated; drawing it
      // with a painter meant re-rasterising a window-sized picture sixty times
      // a second for as long as the camera stayed open.
      await tester.pumpWidget(host(const ScannerOverlayStyle()));

      final boundary = tester.renderObject(lineIn(find.byType(ScannerOverlay)));

      expect(boundary.isRepaintBoundary, isTrue);
      expect(boundary.parent, isA<RenderTransform>());
    });

    testWidgets('is absent when the style turns it off', (tester) async {
      await tester.pumpWidget(
        host(const ScannerOverlayStyle(showScanLine: false)),
      );

      expect(lineIn(find.byType(ScannerOverlay)), findsNothing);
    });
  });

  group('ScannerOverlayStyle', () {
    test('dims to the shade 2.0.x actually rendered', () {
      // The shape used to apply this alpha twice, once filling a saveLayer and
      // again compositing it back, so the screen only ever saw 0x8F. Dropping
      // the layer for performance made the declared value real and the overlay
      // visibly darker; the default is pinned to what users had.
      expect(const ScannerOverlayStyle().overlayColor, const Color(0x8F000000));
    });
  });

  group('ScannerOverlayShape', () {
    ScannerOverlayShape shape({double cutOutHeight = 100}) =>
        ScannerOverlayShape(cutOutWidth: 200, cutOutHeight: cutOutHeight);

    test('two shapes describing the same window are equal', () {
      // ShapeDecoration compares shapes to decide whether the dimmed area has
      // to be repainted, and the overlay builds a fresh one on every rebuild.
      // Without this the dimming repaints whenever anything above it rebuilds.
      expect(shape(), shape());
      expect(shape().hashCode, shape().hashCode);
    });

    test('a shape with a different window is not equal', () {
      expect(shape(), isNot(shape(cutOutHeight: 120)));
    });
  });
}
