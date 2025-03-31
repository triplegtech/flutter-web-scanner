import 'package:flutter/material.dart';
import 'package:omni_qrcode_barcode_web_reader/src/widgets/scanner_overlay_shape.dart';

class BarcodeOverlayWidget extends StatelessWidget {
  const BarcodeOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: ShapeDecoration(
            shape: ScannerOverlayShape(
                cutOutWidth: MediaQuery.sizeOf(context).width * 0.7,
                cutOutHeight: 150,
                cutOutBottomOffset: 20,
                borderColor: Colors.white,
                borderLength: 25,
                borderWidth: 25,
                borderRadius: 8),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.center,
            child: Container(
              height: MediaQuery.sizeOf(context).height * 0.25,
              width: MediaQuery.sizeOf(context).width * 0.75,
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}
