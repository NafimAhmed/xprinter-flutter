import 'package:flutter/material.dart';
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

  Future<void> loadPrinters() async {
    final granted = await printer.requestBluetoothPermissions();
    if (!granted) return;

    devices = await printer.getBondedBluetoothDevices();
    if (mounted) setState(() {});
  }

  Future<void> connect(XPrinterDevice device) async {
    await printer.connectBluetooth(device.address);
    if (mounted) {
      setState(() => status = 'Connected: ${device.name}');
    }
  }

  Future<void> printDemo() async {
    await printer.printTsplLabel(
      const TsplLabel(
        widthMm: 60,
        heightMm: 40,
        elements: [
          TsplText(x: 20, y: 20, text: 'Express ERP'),
          TsplQrCode(x: 20, y: 65, data: 'ITEM-1001|QTY-24'),
          TsplText(x: 170, y: 70, text: 'Item: 1001'),
          TsplText(x: 170, y: 105, text: 'Qty: 24'),
        ],
      ),
    );
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
        appBar: AppBar(title: const Text('xprinter_flutter example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(status),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: loadPrinters,
              child: const Text('Refresh paired printers'),
            ),
            ...devices.map(
              (device) => ListTile(
                title: Text(device.name),
                subtitle: Text(device.address),
                onTap: () => connect(device),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: printDemo,
              child: const Text('Print TSPL demo label'),
            ),
          ],
        ),
      ),
    );
  }
}
