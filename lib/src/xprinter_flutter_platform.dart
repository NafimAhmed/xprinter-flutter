import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import 'models.dart';
import 'raster.dart';

class XPrinterFlutter {
  XPrinterFlutter._();

  static final XPrinterFlutter instance = XPrinterFlutter._();

  static const MethodChannel _channel =
      MethodChannel('xprinter_flutter/methods');
  static const EventChannel _scanChannel =
      EventChannel('xprinter_flutter/bluetooth_scan');
  static const EventChannel _connectionChannel =
      EventChannel('xprinter_flutter/connection_events');

  Stream<XPrinterDevice>? _scanStream;
  Stream<XPrinterConnectionEvent>? _connectionStream;
  String? _lastTransport;
  String? _lastAddress;
  int _lastPort = 9100;

  Future<String?> get platformVersion =>
      _channel.invokeMethod<String>('platformVersion');

  /// Requests CONNECT permission for paired devices, or SCAN + CONNECT
  /// when [forScanning] is true. Avoids prompting for location unnecessarily.
  Future<bool> requestBluetoothPermissions({bool forScanning = false}) async =>
      (await _channel.invokeMethod<bool>(
        'requestBluetoothPermissions',
        {'forScanning': forScanning},
      )) ?? false;

  Future<List<XPrinterDevice>> getBondedBluetoothDevices() async {
    final data =
        await _channel.invokeListMethod<dynamic>('getBondedBluetoothDevices') ??
            const [];

    return data
        .map(
          (e) => XPrinterDevice.fromMap(
            Map<dynamic, dynamic>.from(e as Map),
          ),
        )
        .toList(growable: false);
  }

  Stream<XPrinterDevice> get bluetoothScanResults => _scanStream ??=
      _scanChannel
          .receiveBroadcastStream()
          .where((event) => event is Map && event['event'] == 'device')
          .map(
            (event) => XPrinterDevice.fromMap(
              Map<dynamic, dynamic>.from(event as Map),
            ),
          )
          .asBroadcastStream();

  Stream<XPrinterConnectionEvent> get connectionEvents =>
      _connectionStream ??= _connectionChannel
          .receiveBroadcastStream()
          .where((event) => event is Map)
          .map(
            (event) => XPrinterConnectionEvent.fromMap(
              Map<dynamic, dynamic>.from(event as Map),
            ),
          )
          .asBroadcastStream();

  Future<bool> startBluetoothScan() async =>
      (await _channel.invokeMethod<bool>('startBluetoothScan')) ?? false;

  Future<void> stopBluetoothScan() =>
      _channel.invokeMethod<void>('stopBluetoothScan');

  Future<List<String>> getUsbDevices() async {
    final result = await _channel.invokeListMethod<String>('getUsbDevices');
    return result ?? const <String>[];
  }

  Future<void> connectBluetooth(String macAddress) async {
    if (macAddress.trim().isEmpty) {
      throw ArgumentError.value(macAddress, 'macAddress', 'Cannot be empty.');
    }
    await _channel.invokeMethod<void>(
      'connectBluetooth',
      {'address': macAddress},
    );
    _lastTransport = 'bluetooth';
    _lastAddress = macAddress;
  }

  Future<void> connectNetwork(String host, {int port = 9100}) async {
    if (host.trim().isEmpty || port < 1 || port > 65535) {
      throw ArgumentError('A valid host and TCP port (1-65535) are required.');
    }
    await _channel.invokeMethod<void>(
      'connectNetwork',
      {'host': host, 'port': port},
    );
    _lastTransport = 'ethernet';
    _lastAddress = host;
    _lastPort = port;
  }

  Future<void> connectUsb(String devicePath) async {
    if (devicePath.trim().isEmpty) {
      throw ArgumentError.value(devicePath, 'devicePath', 'Cannot be empty.');
    }
    await _channel.invokeMethod<void>(
      'connectUsb',
      {'path': devicePath},
    );
    _lastTransport = 'usb';
    _lastAddress = devicePath;
  }

  /// Reconnect to the last printer used in this process.
  ///
  /// Deliberately does not resend failed print data: automatic retries can
  /// duplicate physical labels when printer acknowledgement is unavailable.
  Future<bool> reconnect() async {
    final transport = _lastTransport;
    final address = _lastAddress;
    if (transport == null || address == null) return false;
    try {
      switch (transport) {
        case 'bluetooth':
          await connectBluetooth(address);
        case 'ethernet':
          await connectNetwork(address, port: _lastPort);
        case 'usb':
          await connectUsb(address);
        default:
          return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() =>
      _channel.invokeMethod<void>('disconnect');

  Future<bool> isConnected() async =>
      (await _channel.invokeMethod<bool>('isConnected')) ?? false;

  Future<Map<String, dynamic>> getConnectionInfo() async {
    final result =
        await _channel.invokeMapMethod<dynamic, dynamic>('getConnectionInfo');

    return Map<String, dynamic>.from(result ?? const {});
  }

  /// Resolves when bytes are written to the transport, not when paper exits.
  Future<void> printRaw(Uint8List data) {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'Print data cannot be empty.');
    }
    return _channel.invokeMethod<void>(
      'printRaw',
      {'data': data},
    );
  }

  /// Print the first (or selected) PDF page directly to a TSPL label printer.
  ///
  /// Uses [Printing.raster] and never opens the Android system print dialog.
  /// All pixels are scaled to fit; content is not cropped.
  Future<void> printPdf(
    Uint8List pdfBytes, {
    int pageIndex = 0,
    XPrinterRasterOptions options = const XPrinterRasterOptions(),
  }) async {
    if (pdfBytes.isEmpty || pageIndex < 0) {
      throw ArgumentError('Valid PDF bytes and non-negative pageIndex required.');
    }
    options.validate();
    final pages = Printing.raster(
      pdfBytes,
      pages: <int>[pageIndex],
      dpi: options.dpi.toDouble(),
    );
    await for (final page in pages) {
      await printRgbaImage(
        rgba: page.pixels,
        width: page.width,
        height: page.height,
        options: options,
      );
      return;
    }
    throw StateError('PDF page could not be rasterized.');
  }

  /// Print a PNG/JPEG or any image format supported by Flutter's image codec.
  Future<void> printImage(
    Uint8List imageBytes, {
    XPrinterRasterOptions options = const XPrinterRasterOptions(),
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError('Image bytes cannot be empty.');
    }
    options.validate();
    final codec = await ui.instantiateImageCodec(imageBytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final raw = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (raw == null) throw StateError('Unable to decode image RGBA data.');
        await printRgbaImage(
          rgba: raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
          width: frame.image.width,
          height: frame.image.height,
          options: options,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// Encodes pixels off the UI isolate, then sends a single binary TSPL job.
  Future<void> printRgbaImage({
    required Uint8List rgba,
    required int width,
    required int height,
    XPrinterRasterOptions options = const XPrinterRasterOptions(),
  }) async {
    options.validate();
    final bytes = await Isolate.run(
      () => buildTsplRasterCommand(
        rgba: rgba,
        sourceWidth: width,
        sourceHeight: height,
        options: options,
      ),
    );
    await printRaw(bytes);
  }

  Future<void> printRawText(
    String command, {
    Encoding encoding = utf8,
  }) =>
      printRaw(
        Uint8List.fromList(encoding.encode(command)),
      );

  Future<void> printTsplRaw(String command) =>
      printRawText(command);

  /// Calibrates the TSPL gap sensor.
  ///
  /// With no arguments the printer automatically detects the paper and gap
  /// lengths. Optional values are expressed in printer dots, matching the
  /// TSPL GAPDETECT command.
  Future<void> calibrateGapSensor({
    int? paperLengthDots,
    int? gapLengthDots,
  }) {
    final hasPaper = paperLengthDots != null;
    final hasGap = gapLengthDots != null;

    if (hasPaper != hasGap) {
      throw ArgumentError(
        'paperLengthDots and gapLengthDots must be provided together.',
      );
    }

    if (paperLengthDots != null &&
        (paperLengthDots <= 0 || gapLengthDots! <= 0)) {
      throw ArgumentError('Calibration values must be greater than zero.');
    }

    final command = paperLengthDots == null
        ? 'GAPDETECT\r\n'
        : 'GAPDETECT $paperLengthDots,$gapLengthDots\r\n';

    return printTsplRaw(command);
  }

  Future<void> printZplRaw(String command) =>
      printRawText(command);

  Future<void> printCpclRaw(String command) =>
      printRawText(command);

  Future<void> printTsplLabel(TsplLabel label) =>
      _channel.invokeMethod<void>(
        'printTsplLabel',
        label.toMap(),
      );

  Future<void> testPrint({
    double widthMm = 60,
    double heightMm = 40,
    bool useStoredPrinterSettings = true,
  }) =>
      _channel.invokeMethod<void>(
        'testPrint',
        {
          'widthMm': widthMm,
          'heightMm': heightMm,
          'useStoredPrinterSettings': useStoredPrinterSettings,
        },
      );

  Future<void> printPosText(
    String text, {
    int feedLines = 1,
    bool cut = false,
  }) =>
      _channel.invokeMethod<void>(
        'printPosText',
        {
          'text': text,
          'feedLines': feedLines,
          'cut': cut,
        },
      );

  Future<void> printPosQr(
    String data, {
    int feedLines = 1,
    bool cut = false,
  }) =>
      _channel.invokeMethod<void>(
        'printPosQr',
        {
          'data': data,
          'feedLines': feedLines,
          'cut': cut,
        },
      );
}
