enum XPrinterConnectionType { bluetooth, ethernet, usb }

class XPrinterDevice {
  const XPrinterDevice({
    required this.name,
    required this.address,
    required this.bonded,
    this.rssi,
  });

  final String name;
  final String address;
  final bool bonded;
  final int? rssi;

  factory XPrinterDevice.fromMap(Map<dynamic, dynamic> map) => XPrinterDevice(
        name: (map['name'] as String?) ?? 'Unknown',
        address: (map['address'] as String?) ?? '',
        bonded: (map['bonded'] as bool?) ?? false,
        rssi: map['rssi'] as int?,
      );
}

class XPrinterConnectionEvent {
  const XPrinterConnectionEvent({
    required this.code,
    required this.connected,
    this.info,
    this.message,
  });

  final int code;
  final bool connected;
  final String? info;
  final String? message;

  factory XPrinterConnectionEvent.fromMap(Map<dynamic, dynamic> map) =>
      XPrinterConnectionEvent(
        code: (map['code'] as int?) ?? -1,
        connected: (map['connected'] as bool?) ?? false,
        info: map['info'] as String?,
        message: map['message'] as String?,
      );
}

abstract class TsplElement {
  const TsplElement();
  Map<String, Object?> toMap();
}

class TsplText extends TsplElement {
  const TsplText({
    required this.x,
    required this.y,
    required this.text,
    this.font = '3',
    this.rotation = 0,
    this.xScale = 1,
    this.yScale = 1,
  });

  final int x;
  final int y;
  final String text;
  final String font;
  final int rotation;
  final int xScale;
  final int yScale;

  @override
  Map<String, Object?> toMap() => {
        'type': 'text',
        'x': x,
        'y': y,
        'text': text,
        'font': font,
        'rotation': rotation,
        'xScale': xScale,
        'yScale': yScale,
      };
}

class TsplBarcode extends TsplElement {
  const TsplBarcode({
    required this.x,
    required this.y,
    required this.data,
    this.barcodeType = '128',
    this.height = 80,
    this.readable = 2,
    this.rotation = 0,
    this.narrow = 2,
    this.wide = 2,
  });

  final int x;
  final int y;
  final String data;
  final String barcodeType;
  final int height;
  final int readable;
  final int rotation;
  final int narrow;
  final int wide;

  @override
  Map<String, Object?> toMap() => {
        'type': 'barcode',
        'x': x,
        'y': y,
        'data': data,
        'barcodeType': barcodeType,
        'height': height,
        'readable': readable,
        'rotation': rotation,
        'narrow': narrow,
        'wide': wide,
      };
}

class TsplQrCode extends TsplElement {
  const TsplQrCode({
    required this.x,
    required this.y,
    required this.data,
    this.errorCorrection = 'M',
    this.cellWidth = 5,
    this.mode = 'A',
    this.rotation = 0,
  });

  final int x;
  final int y;
  final String data;
  final String errorCorrection;
  final int cellWidth;
  final String mode;
  final int rotation;

  @override
  Map<String, Object?> toMap() => {
        'type': 'qrcode',
        'x': x,
        'y': y,
        'data': data,
        'errorCorrection': errorCorrection,
        'cellWidth': cellWidth,
        'mode': mode,
        'rotation': rotation,
      };
}

class TsplBox extends TsplElement {
  const TsplBox({
    required this.x,
    required this.y,
    required this.xEnd,
    required this.yEnd,
    this.thickness = 2,
  });

  final int x;
  final int y;
  final int xEnd;
  final int yEnd;
  final int thickness;

  @override
  Map<String, Object?> toMap() => {
        'type': 'box',
        'x': x,
        'y': y,
        'xEnd': xEnd,
        'yEnd': yEnd,
        'thickness': thickness,
      };
}

class TsplBar extends TsplElement {
  const TsplBar({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  Map<String, Object?> toMap() => {
        'type': 'bar',
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

class TsplLabel {
  const TsplLabel({
    required this.widthMm,
    required this.heightMm,
    required this.elements,
    this.gapMm = 2,
    this.gapOffsetMm = 0,
    this.offsetMm,
    this.speed = 5,
    this.density = 8,
    this.direction = 0,
    this.referenceX = 0,
    this.referenceY = 0,
    this.copies = 1,
    this.clearBeforePrint = true,
    this.useStoredPrinterSettings = false,
  });

  final double widthMm;
  final double heightMm;
  final List<TsplElement> elements;
  final double gapMm;
  final double gapOffsetMm;
  final double? offsetMm;
  final double speed;
  final int density;
  final int direction;
  final int referenceX;
  final int referenceY;
  final int copies;
  final bool clearBeforePrint;

  /// When true, the print job does not send SIZE, GAP, OFFSET, SPEED,
  /// DENSITY, DIRECTION, or REFERENCE commands. The printer's currently
  /// stored media and print settings are used instead.
  ///
  /// This is useful for printer firmware that enters an error state when
  /// media configuration commands are sent with every job.
  final bool useStoredPrinterSettings;

  Map<String, Object?> toMap() => {
        'widthMm': widthMm,
        'heightMm': heightMm,
        'gapMm': gapMm,
        'gapOffsetMm': gapOffsetMm,
        if (offsetMm != null) 'offsetMm': offsetMm,
        'speed': speed,
        'density': density,
        'direction': direction,
        'referenceX': referenceX,
        'referenceY': referenceY,
        'copies': copies,
        'clearBeforePrint': clearBeforePrint,
        'useStoredPrinterSettings': useStoredPrinterSettings,
        'elements': elements.map((e) => e.toMap()).toList(growable: false),
      };
}
