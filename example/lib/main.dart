import 'package:flutter/material.dart';
import 'package:omni_qrcode_barcode_web_reader/omni_qrcode_barcode_web_reader.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omni Scanner Example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      home: const ScannerDemoPage(),
    );
  }
}

class ScannerDemoPage extends StatefulWidget {
  const ScannerDemoPage({super.key});

  @override
  State<ScannerDemoPage> createState() => _ScannerDemoPageState();
}

class _ScannerDemoPageState extends State<ScannerDemoPage> {
  ScanMode _mode = ScanMode.barcode;
  ScanEngine _engine = ScanEngine.auto;
  final List<BarcodeResult> _results = <BarcodeResult>[];
  ScannerFailure? _failure;

  void _handleDetect(BarcodeResult result) {
    setState(() {
      _results.insert(0, result);
      if (_results.length > 20) _results.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Omni Scanner'),
        actions: [
          PopupMenuButton<ScanEngine>(
            initialValue: _engine,
            tooltip: 'Decoding engine',
            onSelected: (value) => setState(() => _engine = value),
            itemBuilder: (context) => [
              for (final engine in ScanEngine.values)
                PopupMenuItem(value: engine, child: Text(engine.name)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.memory),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SegmentedButton<ScanMode>(
            segments: const [
              ButtonSegment(value: ScanMode.barcode, label: Text('Barcode')),
              ButtonSegment(value: ScanMode.qrCode, label: Text('QR')),
              ButtonSegment(value: ScanMode.all, label: Text('All')),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => setState(() {
              _mode = selection.first;
              _failure = null;
            }),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: OmniWebScanner(
              key: ValueKey('$_mode-$_engine'),
              scanMode: _mode,
              engine: _engine,
              showRetryButton: true,
              onDetect: _handleDetect,
              onError: (failure) => setState(() => _failure = failure),
            ),
          ),
          if (_failure case final failure?)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${failure.kind.name}: ${failure.message}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            flex: 2,
            child: _results.isEmpty
                ? const Center(child: Text('Point the camera at a code'))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          result.checksumVerified
                              ? Icons.verified_outlined
                              : Icons.qr_code_2,
                        ),
                        title: Text(result.value),
                        subtitle: Text(
                          '${result.format.name} · '
                          '${result.confirmations} confirmation(s)'
                          '${result.checksumVerified ? ' · checksum ok' : ''}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
