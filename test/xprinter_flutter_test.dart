import 'package:flutter_test/flutter_test.dart';
import 'package:xprinter_flutter/xprinter_flutter.dart';

void main() {
  test('TSPL label serializes core fields', () {
    const label = TsplLabel(
      widthMm: 60,
      heightMm: 40,
      elements: [TsplText(x: 10, y: 10, text: 'Hello')],
    );

    final map = label.toMap();
    expect(map['widthMm'], 60);
    expect(map['heightMm'], 40);
    expect((map['elements'] as List).length, 1);
  });
}
