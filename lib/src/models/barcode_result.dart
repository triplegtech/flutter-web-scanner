class BarcodeResult {
  final String value;
  final String format;

  BarcodeResult({required this.value, required this.format});

  @override
  String toString() => 'BarcodeResult(value: $value, format: $format)';
}
