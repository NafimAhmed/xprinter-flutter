# xprinter_flutter

Direct Android printing for XPrinter-compatible label and POS printers from Flutter.

`xprinter_flutter` talks directly to the printer over Bluetooth SPP, TCP/IP, or USB. It does not require the XPrinter "Label Printer" Android app and it does not use the Android system print dialog.

## Features

- Android 5.0+ (`minSdk 21`)
- Bluetooth paired-device listing and discovery
- Direct Bluetooth SPP connection
- Direct TCP/IP / Wi-Fi / Ethernet connection (default port `9100`)
- Direct USB bulk connection with Android USB permission handling
- Structured TSPL label printing
  - label size and gap
  - speed and density
  - direction and reference
  - text
  - Code 128 and other printer-supported barcodes
  - QR codes
  - boxes and bars
  - multiple copies
- Direct PDF page printing (no system dialog) with 203-DPI rasterization
- Direct PNG/JPEG and RGBA image printing
- Auto-fit, optional 90° rotation, polarity, threshold, and orientation controls
- Preconfigured XP-365B 75x100 mm bitmap mode
- In-process reconnect to the last successfully connected printer
- Raw TSPL commands
- Raw ZPL commands
- Raw CPCL commands
- Arbitrary raw byte printing
- Basic ESC/POS text and QR printing
- Connection event stream
- No external printing application
- No system print preview/dialog for Bluetooth or TCP/IP printing

## Install

From GitHub (recommended until v0.2.0 is published on pub.dev):

```yaml
dependencies:
  xprinter_flutter:
    git:
      url: https://github.com/NafimAhmed/xprinter-flutter.git
      ref: main
```

When a version is published on pub.dev, you can instead use a normal
versioned package dependency. The GitHub repository branch must contain
the changes you want to use.

Then:

```bash
flutter pub get
```

## Quick start

```dart
import 'package:xprinter_flutter/xprinter_flutter.dart';

final printer = XPrinterFlutter.instance;
```

### Bluetooth

Request the required Bluetooth permission:

```dart
final granted = await printer.requestBluetoothPermissions();

if (!granted) {
  return;
}
```

Get already paired devices:

```dart
final devices = await printer.getBondedBluetoothDevices();

for (final device in devices) {
  print('${device.name} - ${device.address}');
}
```

Connect:

```dart
await printer.connectBluetooth(devices.first.address);
```

Active discovery is also available:

```dart
final subscription = printer.bluetoothScanResults.listen((device) {
  print('${device.name}: ${device.address}');
});

// Active scanning needs SCAN permission in addition to CONNECT.
if (!await printer.requestBluetoothPermissions(forScanning: true)) return;
await printer.startBluetoothScan();

// Later:
await printer.stopBluetoothScan();
await subscription.cancel();
```

### Wi-Fi / Ethernet

Most network label printers listen on TCP port `9100`:

```dart
await printer.connectNetwork('192.168.1.100');
```

Or use another port:

```dart
await printer.connectNetwork(
  '192.168.1.100',
  port: 9100,
);
```

### USB

List compatible USB devices with a bulk OUT endpoint:

```dart
final devices = await printer.getUsbDevices();

if (devices.isNotEmpty) {
  await printer.connectUsb(devices.first);
}
```

Android may show its USB-device permission prompt the first time the app accesses a USB printer. That prompt is Android's hardware permission prompt, not a print dialog.

## Structured TSPL label

```dart
await printer.printTsplLabel(
  const TsplLabel(
    widthMm: 60,
    heightMm: 40,
    gapMm: 2,
    density: 8,
    copies: 1,
    elements: [
      TsplText(
        x: 20,
        y: 20,
        text: 'Express ERP',
        font: '3',
      ),
      TsplQrCode(
        x: 20,
        y: 70,
        data: 'ITEM=100245|QTY=24',
        cellWidth: 4,
      ),
      TsplBarcode(
        x: 180,
        y: 70,
        data: '100245',
        barcodeType: '128',
        height: 70,
      ),
      TsplText(
        x: 180,
        y: 160,
        text: 'Qty: 24',
      ),
    ],
  ),
);
```

TSPL element coordinates are printer dots. Label width, height and gap are in millimetres.

### XP-365B safe stored-settings mode

If your XP-365B prints one label and then latches the ERROR light when a job sends
`SIZE`, `GAP`, or other printer configuration commands, use the printer's saved
settings for each print job:

```dart
await printer.printTsplLabel(
  const TsplLabel(
    widthMm: 60,
    heightMm: 40,
    useStoredPrinterSettings: true,
    elements: [
      TsplText(
        x: 20,
        y: 20,
        text: 'Express ERP',
      ),
    ],
  ),
);
```

When `useStoredPrinterSettings: true`, the job does **not** send `SIZE`, `GAP`,
`OFFSET`, `SPEED`, `DENSITY`, `DIRECTION`, or `REFERENCE`. The printer's
already-saved media and print configuration is left untouched. The width/height fields
remain required by the generic label model but are not transmitted in this mode.

## Gap sensor calibration

For die-cut labels, the printer must be able to detect the physical gap between labels.
Calibrate after changing a roll, or when a label prints successfully and the printer then
stops with the ERROR light on.

```dart
await printer.calibrateGapSensor();
```

This sends TSPL `GAPDETECT` without parameters, so the printer automatically detects
the paper and gap lengths. Calibration feeds labels while the sensor measures the media.

The `widthMm`, `heightMm`, and `gapMm` values used for printing must match the
actual label stock. For continuous paper use `gapMm: 0`.

You can also provide approximate paper and gap lengths in printer dots:

```dart
await printer.calibrateGapSensor(
  paperLengthDots: 320,
  gapLengthDots: 16,
);
```

## Direct PDF and image printing

The package converts a PDF page or an encoded PNG/JPEG into RGBA pixels,
scales the ENTIRE image to the label, and sends a binary TSPL BITMAP job.
It does not open the Android print dialog. PDF rasterization uses the
`printing` package; bitmap conversion runs in a background isolate.

For the XP-365B 75x100 mm label tested in Express ERP, use the printer-specific
preset so the stored paper settings, bit polarity and 180° correction are kept:

```dart
import 'dart:typed_data';
import 'package:xprinter_flutter/xprinter_flutter.dart';

Future<void> printLabel(Uint8List pdfBytes, Uint8List imageBytes) async {
  final printer = XPrinterFlutter.instance;
  // Connect over Bluetooth, USB or Wi-Fi first.
  await printer.printPdf(
    pdfBytes,
    options: const XPrinterRasterOptions.xp365b75x100(),
  );

  // Or print a JPG/PNG with the same settings:
  await printer.printImage(
    imageBytes,
    options: const XPrinterRasterOptions.xp365b75x100(),
  );
}
```

For other TSPL printers choose dimensions, DPI, orientation and polarity
explicitly. The default options are generic and may not match your printer's
bitmap polarity.

```dart
await printer.printPdf(
  pdfBytes,
  options: const XPrinterRasterOptions(
    widthMm: 60,
    heightMm: 40,
    dpi: 203,
    autoRotate: true,
    rotate180: false,
    invertedBits: false,
    useStoredPrinterSettings: true,
    copies: 1,
  ),
);
```

Only one PDF page per call is printed (default page index 0). These APIs
confirm delivery to the transport, NOT that a physical label exited the printer.
Do not automatically retry an uncertain write without checking for duplicates.

### Reconnect after disconnection

```dart
final reconnected = await printer.reconnect();
if (reconnected) {
  // Explicitly decide whether a failed job needs to be retried.
}
```

The last successful address/USB path is remembered only while the Flutter
process is running, not saved permanently to device storage.

## Raw TSPL

Use this when you need a command that is not represented by the structured API:

```dart
await printer.printTsplRaw('''
SIZE 60 mm,40 mm
GAP 2 mm,0 mm
DENSITY 8
CLS
TEXT 20,20,"3",0,1,1,"Express ERP"
QRCODE 20,70,M,5,A,0,"ITEM-100245"
PRINT 1,1
''');
```

## Raw ZPL

```dart
await printer.printZplRaw(
  '^XA^FO30,30^ADN,36,20^FDExpress ERP^FS^XZ',
);
```

## Raw CPCL

```dart
await printer.printCpclRaw(
  '! 0 200 200 300 1\r\n'
  'TEXT 4 0 30 40 Express ERP\r\n'
  'FORM\r\n'
  'PRINT\r\n',
);
```

## Raw bytes

```dart
await printer.printRaw(bytes);
```

## ESC/POS

Text:

```dart
await printer.printPosText(
  'Express ERP\nGRN: 100001',
  feedLines: 2,
  cut: false,
);
```

QR:

```dart
await printer.printPosQr(
  'GRN=100001',
  feedLines: 2,
);
```

## Test print

After connecting:

```dart
await printer.testPrint(
  widthMm: 60,
  heightMm: 40,
  useStoredPrinterSettings: true, // default; safe for XP-365B
);
```

## Connection state

```dart
final connected = await printer.isConnected();
final info = await printer.getConnectionInfo();
```

Connection changes can also be observed:

```dart
printer.connectionEvents.listen((event) {
  print(
    'connected=${event.connected}, '
    'info=${event.info}, '
    'message=${event.message}',
  );
});
```

## Express ERP example

```dart
Future<void> printGrnLabel({
  required String grnNo,
  required String poNo,
  required String itemCode,
  required double qty,
}) async {
  final printer = XPrinterFlutter.instance;

  if (!await printer.isConnected()) {
    // Reconnect to the MAC/IP saved by your ERP before printing.
    throw StateError('Printer is not connected');
  }

  await printer.printTsplLabel(
    TsplLabel(
      widthMm: 60,
      heightMm: 40,
      gapMm: 2,
      density: 8,
      elements: [
        const TsplText(
          x: 20,
          y: 15,
          text: 'EXPRESS ERP',
        ),
        TsplText(
          x: 20,
          y: 50,
          text: 'GRN: $grnNo',
        ),
        TsplText(
          x: 20,
          y: 80,
          text: 'PO: $poNo',
        ),
        TsplText(
          x: 20,
          y: 110,
          text: 'Item: $itemCode',
        ),
        TsplText(
          x: 20,
          y: 140,
          text: 'Qty: $qty',
        ),
        TsplQrCode(
          x: 300,
          y: 40,
          data: '$grnNo|$poNo|$itemCode|$qty',
          cellWidth: 4,
        ),
      ],
    ),
  );
}
```

This allows a flow such as:

```text
Express ERP
    ↓
API success
    ↓
Build label
    ↓
xprinter_flutter
    ↓
Bluetooth / Wi-Fi / USB
    ↓
XPrinter
```

## Android permissions

On Android 12 and newer, Bluetooth uses:

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`

The scan permission is declared with `neverForLocation`, so the plugin does not request location permission on Android 12+.

On Android 6 through Android 11, Android's classic Bluetooth discovery API requires location permission. The plugin limits `ACCESS_FINE_LOCATION` to SDK 30 and below.

TCP/IP printing only requires network access.

## Compatibility

The transport layer is generic, but the command language still has to be supported by your printer firmware.

- Use TSPL with TSPL/TSPL2-compatible XPrinter label printers.
- Use ZPL only on models/firmware that support ZPL.
- Use CPCL only on models/firmware that support CPCL.
- Use ESC/POS helpers with compatible POS/receipt printers.

The implementation was designed against the APIs and command examples supplied with XPrinter Android SDK 3.5.8, but **no vendor AAR or proprietary binary is bundled in this repository**.

## Current limitations

- Android only; native iOS/macOS/Windows transports are not implemented.
- Serial-port transport is not included.
- Firmware, paper-out, cover-open, and physical print-complete queries are not implemented.
- The binary TSPL bitmap path is available through `printPdf`, `printImage`
  and `printRgbaImage`, but there is no structured `TsplImage` element yet.
- There is no persistent job queue or print-complete acknowledgement; callers
  must not assume a successful write means paper was printed.
- Direct PDF/image printing is for TSPL printers. ZPL, CPCL and ESC/POS still
  have raw command support, but are not automatically rasterized by these APIs.

## Quality checks

```bash
flutter pub get
flutter analyze
flutter test
cd example
flutter pub get
flutter test
flutter build apk --debug
```

The included GitHub Actions workflow runs these checks on pull requests.
Hardware printing must still be tested on each supported printer model.

## License

The plugin source is MIT licensed. XPrinter names, manuals, firmware and SDKs remain the property of their respective owners. No XPrinter SDK binary is redistributed by this package.
