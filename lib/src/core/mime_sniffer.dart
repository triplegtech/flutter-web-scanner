import 'dart:typed_data';

/// Identifies image formats from their magic bytes.
///
/// The browser needs a correct MIME type on the `Blob` before it will decode
/// bytes into an `<img>`, and callers hand us raw `Uint8List` with no type
/// information (file pickers, network responses, clipboard paste). Sniffing is
/// the only reliable way to recover it — trusting a filename extension is how
/// a mislabelled `.jpg` that is really a PNG ends up silently failing to
/// decode.
abstract final class MimeSniffer {
  /// MIME types the decoding engines can actually turn into an image.
  static const Set<String> decodableImageTypes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/bmp',
    'image/webp',
    'image/tiff',
    'image/heic',
  };

  /// Returns the MIME type implied by [bytes], or `null` when unrecognised.
  static String? sniff(Uint8List bytes) {
    if (_matches(
        bytes, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (_matches(bytes, const [0xFF, 0xD8, 0xFF])) {
      return 'image/jpeg';
    }
    if (_matchesAscii(bytes, 'GIF87a') || _matchesAscii(bytes, 'GIF89a')) {
      return 'image/gif';
    }
    if (_matches(bytes, const [0x42, 0x4D])) {
      return 'image/bmp';
    }
    // WEBP is a RIFF container; the format tag sits at offset 8.
    if (_matchesAscii(bytes, 'RIFF') && _matchesAscii(bytes, 'WEBP', 8)) {
      return 'image/webp';
    }
    if (_matches(bytes, const [0x49, 0x49, 0x2A, 0x00]) ||
        _matches(bytes, const [0x4D, 0x4D, 0x00, 0x2A])) {
      return 'image/tiff';
    }
    // ISO-BMFF: 4-byte size, then 'ftyp', then the brand.
    if (_matchesAscii(bytes, 'ftyp', 4) && _isHeifBrand(bytes)) {
      return 'image/heic';
    }
    if (_matchesAscii(bytes, '%PDF')) {
      return 'application/pdf';
    }
    return null;
  }

  /// Whether [bytes] look like an image the engines can decode.
  static bool isDecodableImage(Uint8List bytes) {
    final mime = sniff(bytes);
    return mime != null && decodableImageTypes.contains(mime);
  }

  /// Conventional file extension for [mimeType], used when naming the
  /// synthetic `File` handed to the browser.
  static String extensionFor(String mimeType) => switch (mimeType) {
        'image/png' => 'png',
        'image/jpeg' => 'jpg',
        'image/gif' => 'gif',
        'image/bmp' => 'bmp',
        'image/webp' => 'webp',
        'image/tiff' => 'tiff',
        'image/heic' => 'heic',
        'application/pdf' => 'pdf',
        _ => 'bin',
      };

  static const Set<String> _heifBrands = {
    'heic',
    'heix',
    'hevc',
    'hevx',
    'heim',
    'heis',
    'mif1',
    'msf1',
  };

  static bool _isHeifBrand(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    return _heifBrands.contains(brand);
  }

  static bool _matches(Uint8List bytes, List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  static bool _matchesAscii(Uint8List bytes, String text, [int offset = 0]) =>
      _matches(bytes, text.codeUnits, offset);
}
