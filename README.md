# xprinter_flutter

Android Flutter plugin for direct XPrinter printing without opening an external print app or Android print dialog.

The plugin wraps the XPrinter Android SDK 3.5.8 and exposes Bluetooth, TCP/IP, USB and serial connections plus TSPL label printing, raw ZPL/CPCL commands and basic ESC/POS printing.

## Features

- Bluetooth paired printers and discovery
- Bluetooth direct connection
- TCP/IP / Wi-Fi / Ethernet direct connection
- USB direct connection
- Serial connection
- TSPL labels: size, gap, speed, density, direction and reference
- TSPL text, barcode, QR code, box, bar and bitmap elements
- Raw TSPL / ZPL / CPCL / byte commands
- Printer status, serial number and firmware query
- Basic ESC/POS text and QR printing
- No external Label Printer app required
- No Android system print dialog
- Android 5.0+ (minSdk 21)

## Install

```yaml
dependencies:
  xprinter_flutter:
    git:
      url: https://github.com/NafimAhmed/xprinter-flutter.git
```

The repository currently includes `printer-lib-3.5.8.aar` under `android/libs/` because the plugin is a wrapper around that SDK. Review the vendor's SDK redistribution terms before publishing this package to pub.dev or redistributing the AAR.

## Bluetooth permissions

Call once before Bluetooth scan/connect:

```dart
final printer = XPrinterFlutter.instance;
final granted = await printer.requestBluetoothPermissions();
```

Android 12+ requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`. The plugin marks scanning as `neverForLocation`; location permission is only used for Bluetooth discovery on Android 6-11.

## Connect via Bluetooth

```dart
final printer = XPrinterFlutter.instance;

await printer.requestBluetoothPermissions();
final devices = await printer.getBondedBluetoothDevices();

await printer.connectBluetooth(devices.first.address);
```

For active discovery:

```dart
final subscription = printer.bluetoothScanResults.listen((device) {
  print('${device.name}: ${device.address}');
});

await printer.startBluetoothScan();
```

## Connect via Wi-Fi / Ethernet

```dart
await printer.connectNetwork('192.168.1.100');
```

Custom port:

```dart
await printer.connectNetwork('192.168.1.100', port: 9100);
```

## Connect via USB

```dart
final usb = await printer.getUsbDevices();
await printer.connectUsb(usb.first);
```

The vendor SDK may show the Android USB permission dialog the first time a USB device is accessed. Bluetooth and TCP/IP printing can run without a print dialog after permission/connection setup.

## Print a TSPL label

```dart
await printer.printTsplLabel(
  const TsplLabel(
    widthMm: 60,
    heightMm: 40,
    gapMm: 2,
    density: 8,
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
      ),
      TsplBarcode(
        x: 180,
        y: 70,
        data: '100245',
        barcodeType: '128',
      ),
    ],
  ),
);
```

## Raw TSPL

```dart
await printer.printTsplRaw('''
SIZE 60 mm,40 mm
GAP 2 mm,0 mm
CLS
TEXT 20,20,"3",0,1,1,"Express ERP"
QRCODE 20,70,M,5,A,0,"ITEM-100245"
PRINT 1,1
''');
```

## Raw ZPL / CPCL

```dart
await printer.printZplRaw('^XA^FO30,30^ADN,36,20^FDExpress ERP^FS^XZ');
await printer.printCpclRaw('! 0 200 200 300 1\r\nTEXT 4 0 30 40 Express ERP\r\nFORM\r\nPRINT\r\n');
```

## Printer status

```dart
final status = await printer.getTsplStatus();
if (status.isReady) {
  print('Ready');
}
```

TSPL status bits exposed by `XPrinterStatus` include `headOpen`, `paperJam`, `outOfPaper`, `outOfRibbon`, `paused`, and `printing`.

## Express ERP example

```dart
Future<void> printGrnLabel({
  required String grnNo,
  required String poNo,
  required String itemCode,
  required double qty,
}) async {
  await XPrinterFlutter.instance.printTsplLabel(
    TsplLabel(
      widthMm: 60,
      heightMm: 40,
      elements: [
        const TsplText(x: 20, y: 15, text: 'EXPRESS ERP'),
        TsplText(x: 20, y: 50, text: 'GRN: $grnNo'),
        TsplText(x: 20, y: 80, text: 'PO: $poNo'),
        TsplText(x: 20, y: 110, text: 'Item: $itemCode'),
        TsplText(x: 20, y: 140, text: 'Qty: $qty'),
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

## Notes

- XPrinter models differ in firmware and supported command languages. Use TSPL only on a TSPL-compatible label printer; use ZPL/CPCL only when your model supports them.
- Coordinate units in TSPL are printer dots, while label size/gap are configured in millimetres.
- For stable production printing, save the printer MAC/IP in your app and reconnect when `isConnected` is false.
- USB permission is controlled by Android and may require user approval when the device is first connected.

## License

The Dart/Kotlin wrapper source in this repository is MIT licensed. The bundled XPrinter SDK/AAR is third-party vendor software and is **not** relicensed under MIT. See `THIRD_PARTY_NOTICES.md`.
