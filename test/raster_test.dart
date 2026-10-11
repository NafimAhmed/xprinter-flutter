import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xprinter_flutter/xprinter_flutter.dart';

void main() {
  test('1 mm 203-DPI black RGBA image encodes to 8x8 black pixels', () {
    final command = buildTsplRasterCommand(
      rgba: Uint8List.fromList([0, 0, 0, 255]),
      sourceWidth: 1,
      sourceHeight: 1,
      options: const XPrinterRasterOptions(
        widthMm: 1,
        heightMm: 1,
        autoRotate: false,
      ),
    );

    final prefix = 'CLS\r\nBITMAP 0,0,1,8,0,'.codeUnits;
    expect(command.sublist(0, prefix.length), prefix);
    expect(command.sublist(prefix.length, prefix.length + 8),
        List<int>.filled(8, 0xFF));
    expect(command.sublist(prefix.length + 8),
        '\r\nPRINT 1,1\r\n'.codeUnits);
  });

  test('XP-365B preset uses inverted bitmap polarity', () {
    const options = XPrinterRasterOptions.xp365b75x100();
    expect(options.invertedBits, isTrue);
    expect(options.rotate180, isTrue);
    expect(options.useStoredPrinterSettings, isTrue);
    final command = buildTsplRasterCommand(
      rgba: Uint8List.fromList([0, 0, 0, 255]),
      sourceWidth: 1,
      sourceHeight: 1,
      options: options,
    );
    final prefix = 'CLS\r\nBITMAP 0,0,75,800,0,'.codeUnits;
    expect(command.sublist(0, prefix.length), prefix);
    // The label is vertically centered, so some rows remain white.
    expect(command[prefix.length], 0xFF);
    expect(command.sublist(prefix.length).contains(0), isTrue);
  });

  test('Transparent black does not print', () {
    final command = buildTsplRasterCommand(
      rgba: Uint8List.fromList([0, 0, 0, 0]),
      sourceWidth: 1,
      sourceHeight: 1,
      options: const XPrinterRasterOptions(widthMm: 1, heightMm: 1),
    );
    final prefix = 'CLS\r\nBITMAP 0,0,1,8,0,'.codeUnits;
    expect(command.sublist(prefix.length, prefix.length + 8),
        List<int>.filled(8, 0));
  });

  test('Stored settings prevent SIZE / GAP changes', () {
    final command = buildTsplRasterCommand(
      rgba: Uint8List.fromList([255, 255, 255, 255]),
      sourceWidth: 1,
      sourceHeight: 1,
      options: const XPrinterRasterOptions(widthMm: 1, heightMm: 1),
    );
    expect(String.fromCharCodes(command.take(10)), startsWith('CLS'));
  });

  test('XP-365B presets can adjust copies without losing polarity', () {
    final settings = const XPrinterRasterOptions.xp365b75x100()
        .copyWith(copies: 3, threshold: 160);
    expect(settings.copies, 3);
    expect(settings.threshold, 160);
    expect(settings.widthMm, 75);
    expect(settings.heightMm, 100);
    expect(settings.rotate180, isTrue);
    expect(settings.invertedBits, isTrue);
  });

  test('Encoder validates image buffers and label options', () {
    expect(
      () => buildTsplRasterCommand(
        rgba: Uint8List(3),
        sourceWidth: 1,
        sourceHeight: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => const XPrinterRasterOptions(dpi: 0).validate(),
      throwsArgumentError,
    );
  });
}
