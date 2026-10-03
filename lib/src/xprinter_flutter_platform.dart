import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'models.dart';

class XPrinterFlutter {
  XPrinterFlutter._();

  static final XPrinterFlutter instance = XPrinterFlutter._();

  static const MethodChannel _channel = MethodChannel('xprinter_flutter/methods');
  static const EventChannel _scanChannel =
      EventChannel('xprinter_flutter/bluetooth_scan');
  static const EventChannel _connectionChannel =
      EventChannel('xprinter_flutter/connection_events');

  Stream<XPrinterDevice>? _scanStream;
  Stream<XPrinterConnectionEvent>? _connectionStream;

  Future<String?> get platformVersion =>
      _channel.invokeMethod<String>('platformVersion');

  Future<bool> requestBluetoothPermissions() async =>
      (await _channel.invokeMethod<bool>('requestBluetoothPermissions')) ?? false;

  Future<List<XPrinterDevice>> getBondedBluetoothDevices() async {
    final data =
        await _channel.invokeListMethod<dynamic>('getBondedBluetoothDevices') ??
            const [];
    return data
        .map((e) =>
            XPrinterDevice.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Stream<XPrinterDevice> get bluetoothScanResults => _scanStream ??= _scanChannel
      .receiveBroadcastStream()
      .where((event) => event is Map && event['event'] == 'device')
      .map((event) =>
          XPrinterDevice.fromMap(Map<dynamic, dynamic>.from(event as Map)))
      .asBroadcastStream();

  Stream<XPrinterConnectionEvent> get connectionEvents =>
      _connectionStream ??= _connectionChannel
          .receiveBroadcastStream()
          .where((event) => event is Map)
          .map((event) => XPrinterConnectionEvent.fromMap(
              Map<dynamic, dynamic>.from(event as Map)))
          .asBroadcastStream();

  Future<bool> startBluetoothScan() async =>
      (await _channel.invokeMethod<bool>('startBluetoothScan')) ?? false;

  Future<void> stopBluetoothScan() =>
      _channel.invokeMethod<void>('stopBluetoothScan');

  Future<List<String>> getUsbDevices() async {
    final result = await _channel.invokeListMethod<String>('getUsbDevices');
    return result ?? const <String>[];
  }

  Future<List<String>> getSerialPorts() async {
    final result = await _channel.invokeListMethod<String>('getSerialPorts');
    return result ?? const <String>[];
  }

  Future<void> connectBluetooth(String macAddress) =>
      _channel.invokeMethod<void>(
          'connectBluetooth', {'address': macAddress});

  Future<void> connectNetwork(String host, {int? port}) =>
      _channel.invokeMethod<void>('connectNetwork', {
        'host': host,
        if (port != null) 'port': port,
      });

  Future<void> connectUsb(String devicePath) =>
      _channel.invokeMethod<void>('connectUsb', {'path': devicePath});

  Future<void> connectSerial(String port, {int baudRate = 9600}) =>
      _channel.invokeMethod<void>('connectSerial', {
        'port': port,
        'baudRate': baudRate,
      });

  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');

  Future<bool> isConnected() async =>
      (await _channel.invokeMethod<bool>('isConnected')) ?? false;

  Future<Map<String, dynamic>> getConnectionInfo() async {
    final result =
        await _channel.invokeMapMethod<dynamic, dynamic>('getConnectionInfo');
    return Map<String, dynamic>.from(result ?? const {});
  }

  Future<void> printRaw(Uint8List data) =>
      _channel.invokeMethod<void>('printRaw', {'data': data});

  Future<void> printRawText(String command, {Encoding encoding = utf8}) =>
      printRaw(Uint8List.fromList(encoding.encode(command)));

  Future<void> printTsplRaw(String command) => printRawText(command);
  Future<void> printZplRaw(String command) => printRawText(command);
  Future<void> printCpclRaw(String command) => printRawText(command);

  Future<void> printTsplLabel(TsplLabel label) =>
      _channel.invokeMethod<void>('printTsplLabel', label.toMap());

  Future<void> testPrint({double widthMm = 60, double heightMm = 40}) =>
      _channel.invokeMethod<void>('testPrint', {
        'widthMm': widthMm,
        'heightMm': heightMm,
      });

  Future<XPrinterStatus> getTsplStatus({int timeoutMs = 1500}) async {
    final code = await _channel
        .invokeMethod<int>('getTsplStatus', {'timeoutMs': timeoutMs});
    return XPrinterStatus(code ?? -1);
  }

  Future<String?> getSerialNumber() =>
      _channel.invokeMethod<String>('getSerialNumber');

  Future<String?> getFirmwareVersion() =>
      _channel.invokeMethod<String>('getFirmwareVersion');

  Future<void> printPosText(
    String text, {
    int feedLines = 1,
    bool cut = false,
  }) =>
      _channel.invokeMethod<void>('printPosText', {
        'text': text,
        'feedLines': feedLines,
        'cut': cut,
      });

  Future<void> printPosQr(
    String data, {
    int feedLines = 1,
    bool cut = false,
  }) =>
      _channel.invokeMethod<void>('printPosQr', {
        'data': data,
        'feedLines': feedLines,
        'cut': cut,
      });
}
