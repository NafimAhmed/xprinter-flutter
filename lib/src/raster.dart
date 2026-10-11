import 'dart:math' as math;
import 'dart:typed_data';

/// Settings for printing rasterized PDFs and images to TSPL-compatible printers.
///
/// Use [XPrinterRasterOptions.xp365b75x100] when using the tested XP-365B
/// 75x100 mm label configuration; other printers may use the opposite bit
/// polarity or orientation.
class XPrinterRasterOptions {
  const XPrinterRasterOptions({
    this.widthMm = 75,
    this.heightMm = 100,
    this.dpi = 203,
    this.autoRotate = true,
    this.rotate180 = false,
    this.invertedBits = false,
    this.useStoredPrinterSettings = true,
    this.gapMm = 2,
    this.threshold = 185,
    this.copies = 1,
  });

  /// Matches the known-good XP-365B bitmap polarity and orientation.
  const XPrinterRasterOptions.xp365b75x100()
      : widthMm = 75,
        heightMm = 100,
        dpi = 203,
        autoRotate = true,
        rotate180 = true,
        invertedBits = true,
        useStoredPrinterSettings = true,
        gapMm = 2,
        threshold = 185,
        copies = 1;

  final double widthMm;
  final double heightMm;
  final int dpi;
  final bool autoRotate;
  final bool rotate180;

  /// Some printer firmware treats cleared bits as black rather than set bits.
  final bool invertedBits;

  /// Preserve media settings already calibrated on the printer.
  final bool useStoredPrinterSettings;
  final double gapMm;
  final int threshold;
  final int copies;

  void validate() {
    if (!widthMm.isFinite || widthMm <= 0 ||
        !heightMm.isFinite || heightMm <= 0) {
      throw ArgumentError('Label dimensions must be finite and positive.');
    }
    if (dpi < 72 || dpi > 1200) {
      throw ArgumentError.value(dpi, 'dpi', 'Must be between 72 and 1200.');
    }
    if (!gapMm.isFinite || gapMm < 0) {
      throw ArgumentError.value(gapMm, 'gapMm', 'Must be non-negative.');
    }
    if (threshold < 0 || threshold > 255) {
      throw ArgumentError.value(threshold, 'threshold', 'Must be 0-255.');
    }
    if (copies < 1 || copies > 999) {
      throw ArgumentError.value(copies, 'copies', 'Must be 1-999.');
    }
  }
}

/// Encode RGBA pixels (four bytes per pixel) as binary TSPL BITMAP commands.
///
/// Scales the COMPLETE source to the chosen label (never crops). If enabled,
/// 90-degree clockwise rotation is selected only when it improves the fit.
/// The resulting bytes contain one TSPL command/job, including embedded binary
/// bitmap data; send them with XPrinterFlutter.printRaw().
Uint8List buildTsplRasterCommand({
  required Uint8List rgba,
  required int sourceWidth,
  required int sourceHeight,
  XPrinterRasterOptions options = const XPrinterRasterOptions(),
}) {
  options.validate();
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    throw ArgumentError('Image dimensions must be positive.');
  }
  final pixelCount = sourceWidth * sourceHeight;
  if (rgba.lengthInBytes < pixelCount * 4) {
    throw ArgumentError('RGBA buffer is smaller than width * height * 4.');
  }

  final widthDots = (options.widthMm * options.dpi / 25.4).round();
  final heightDots = (options.heightMm * options.dpi / 25.4).round();
  if (widthDots <= 0 || heightDots <= 0 ||
      widthDots > 16384 || heightDots > 16384) {
    throw ArgumentError('Requested label dimensions exceed bitmap limits.');
  }

  final widthBytes = (widthDots + 7) ~/ 8;
  final bitmap = Uint8List(widthBytes * heightDots);
  if (options.invertedBits) {
    bitmap.fillRange(0, bitmap.length, 0xFF);
  }

  final normalScale = math.min(
    widthDots / sourceWidth,
    heightDots / sourceHeight,
  );
  final rotatedScale = math.min(
    widthDots / sourceHeight,
    heightDots / sourceWidth,
  );
  final rotate = options.autoRotate && rotatedScale > normalScale;
  final logicalWidth = rotate ? sourceHeight : sourceWidth;
  final logicalHeight = rotate ? sourceWidth : sourceHeight;
  final scale = rotate ? rotatedScale : normalScale;

  final outWidth = (logicalWidth * scale).round().clamp(1, widthDots);
  final outHeight = (logicalHeight * scale).round().clamp(1, heightDots);
  final offsetX = (widthDots - outWidth) ~/ 2;
  final offsetY = (heightDots - outHeight) ~/ 2;

  for (var y = 0; y < outHeight; y++) {
    for (var x = 0; x < outWidth; x++) {
      final int sourceX;
      final int sourceY;
      if (rotate) {
        sourceX = ((y * sourceWidth) ~/ outHeight).clamp(0, sourceWidth - 1);
        sourceY = sourceHeight - 1 -
            ((x * sourceHeight) ~/ outWidth).clamp(0, sourceHeight - 1);
      } else {
        sourceX = ((x * sourceWidth) ~/ outWidth).clamp(0, sourceWidth - 1);
        sourceY = ((y * sourceHeight) ~/ outHeight).clamp(0, sourceHeight - 1);
      }

      final index = (sourceY * sourceWidth + sourceX) * 4;
      final alpha = rgba[index + 3];
      if (alpha == 0) continue;
      // Alpha composite onto white: transparent dark pixels are not printed.
      final r = (rgba[index] * alpha + 255 * (255 - alpha)) ~/ 255;
      final g = (rgba[index + 1] * alpha + 255 * (255 - alpha)) ~/ 255;
      final b = (rgba[index + 2] * alpha + 255 * (255 - alpha)) ~/ 255;
      final luminance = (r * 299 + g * 587 + b * 114) ~/ 1000;
      if (luminance >= options.threshold) continue;

      var dstX = offsetX + x;
      var dstY = offsetY + y;
      if (options.rotate180) {
        dstX = widthDots - 1 - dstX;
        dstY = heightDots - 1 - dstY;
      }

      final byteIndex = dstY * widthBytes + dstX ~/ 8;
      final mask = 0x80 >> (dstX % 8);
      if (options.invertedBits) {
        bitmap[byteIndex] &= 0xFF ^ mask;
      } else {
        bitmap[byteIndex] |= mask;
      }
    }
  }

  final commands = BytesBuilder(copy: false);
  if (!options.useStoredPrinterSettings) {
    commands.add((
      'SIZE ${options.widthMm} mm,${options.heightMm} mm\r\n'
      'GAP ${options.gapMm} mm,0 mm\r\n'
    ).codeUnits);
  }
  commands.add('CLS\r\nBITMAP 0,0,$widthBytes,$heightDots,0,'.codeUnits);
  commands.add(bitmap);
  commands.add('\r\nPRINT 1,${options.copies}\r\n'.codeUnits);
  return commands.takeBytes();
}
