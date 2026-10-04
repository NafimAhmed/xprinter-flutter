import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xprinter_flutter/xprinter_flutter.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final printer = XPrinterFlutter.instance;

  List<XPrinterDevice> devices = const [];
  String status = 'Disconnected';
  bool busy = false;

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> loadPrinters() async {
    try {
      setState(() => busy = true);

      final granted = await printer.requestBluetoothPermissions();
      if (!granted) {
        setState(() => status = 'Bluetooth permission denied');
        return;
      }

      final result = await printer.getBondedBluetoothDevices();

      if (!mounted) return;
      setState(() {
        devices = result;
        status = result.isEmpty
            ? 'No paired printers. Pair XP-365B in Android Bluetooth settings first.'
            : 'Select XP-365B and tap Connect';
      });
    } on PlatformException catch (e) {
      setState(() => status = 'Error: ${e.message ?? e.code}');
      showMessage(status);
    } catch (e) {
      setState(() => status = 'Error: $e');
      showMessage(status);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect(XPrinterDevice device) async {
    try {
      setState(() {
        busy = true;
        status = 'Connecting to ${device.name}...';
      });

      await printer.connectBluetooth(device.address);

      final connected = await printer.isConnected();

      if (!mounted) return;
      setState(() {
        status = connected
            ? 'Connected: ${device.name} (${device.address})'
            : 'Connection failed: ${device.name}';
      });

      if (connected) {
        showMessage('XP-365B connected successfully');
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => status = 'Connect error: ${e.message ?? e.code}');
      showMessage(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'Connect error: $e');
      showMessage(status);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> ensureConnected() async {
    final connected = await printer.isConnected();
    if (!connected) {
      setState(() => status = 'Printer is not connected');
      showMessage('Connect XP-365B first');
    }
    return connected;
  }

  Future<void> printTsplDemo() async {
    if (!await ensureConnected()) return;

    try {
      setState(() {
        busy = true;
        status = 'Sending TSPL label...';
      });

      await printer.printTsplRaw(
        'SIZE 60 mm,40 mm\r\n'
        'GAP 2 mm,0 mm\r\n'
        'SPEED 4\r\n'
        'DENSITY 8\r\n'
        'DIRECTION 1\r\n'
        'CLS\r\n'
        'TEXT 20,20,"3",0,1,1,"XP-365B TEST"\r\n'
        'TEXT 20,60,"3",0,1,1,"xprinter_flutter"\r\n'
        'QRCODE 20,100,M,4,A,0,"XP365B-TEST-001"\r\n'
        'BARCODE 180,100,"128",60,1,0,2,2,"1234567890"\r\n'
        'PRINT 1,1\r\n',
      );

      if (!mounted) return;
      setState(() => status = 'TSPL data sent successfully');
      showMessage(
        'TSPL sent. If nothing prints, switch XP-365B to LABEL mode.',
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => status = 'TSPL error: ${e.message ?? e.code}');
      showMessage(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'TSPL error: $e');
      showMessage(status);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> printEscPosDemo() async {
    if (!await ensureConnected()) return;

    try {
      setState(() {
        busy = true;
        status = 'Sending ESC/POS receipt test...';
      });

      await printer.printPosText(
        'XP-365B ESC/POS TEST\n'
        'xprinter_flutter\n'
        '1234567890\n',
        feedLines: 3,
      );

      if (!mounted) return;
      setState(() => status = 'ESC/POS data sent successfully');
      showMessage(
        'ESC/POS sent. If this prints but TSPL does not, printer is in RECEIPT mode.',
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => status = 'ESC/POS error: ${e.message ?? e.code}');
      showMessage(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'ESC/POS error: $e');
      showMessage(status);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    await printer.disconnect();
    if (!mounted) return;
    setState(() => status = 'Disconnected');
  }

  @override
  void initState() {
    super.initState();
    loadPrinters();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('xprinter_flutter - XP-365B test'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  status,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : loadPrinters,
              child: const Text('Refresh paired printers'),
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'XP-365B not shown? Pair it first from Android Settings > Bluetooth.',
                ),
              ),
            ...devices.map(
              (device) => Card(
                child: ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.address),
                  trailing: FilledButton.tonal(
                    onPressed: busy ? null : () => connect(device),
                    child: const Text('Connect'),
                  ),
                ),
              ),
            ),
            const Divider(height: 32),
            FilledButton(
              onPressed: busy ? null : printTsplDemo,
              child: const Text('Print TSPL label test'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: busy ? null : printEscPosDemo,
              child: const Text('Print ESC/POS receipt test'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: busy ? null : disconnect,
              child: const Text('Disconnect'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Diagnosis:\n'
              '1. Connect XP-365B first.\n'
              '2. If TSPL prints: label mode is working.\n'
              '3. If ESC/POS prints but TSPL does not: switch printer to LABEL mode.\n'
              '4. If neither prints but app says Connected: Bluetooth transport/firmware needs further checking.',
            ),
          ],
        ),
      ),
    );
  }
}
