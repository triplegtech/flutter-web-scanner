import 'package:flutter/material.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Example Page'),
      ),
      body: OmniWebScanner(
        onDetect: (error) {},
        onError: (barcode) {},
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        overlay: ScanMode.Barcode,
        placeholder: Text('Place Holder'),
      ),
    );
  }
}
