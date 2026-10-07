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
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  final widthController = TextEditingController(text: '60');
  final heightController = TextEditingController(text: '40');
  final gapController = TextEditingController(text: '2');

  List<XPrinterDevice> devices = const [];
  String status = 'Disconnected';
  bool busy = false;

  void showMessage(String message) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double readPositiveMm(
    TextEditingController controller,
    String fieldName,
  ) {
    final value = double.tryParse(controller.text.trim());
    if (value == null || value <= 0) {
      throw FormatException('$fieldName must be greater than 0 mm');
    }
    return value;
  }

  double readGapMm() {
    final value = double.tryParse(gapController.text.trim());
    if (value == null || value < 0) {
      throw const FormatException('Gap must be 0 mm or greater');
    }
    return value;
  }

  String formatMm(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
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
      if (!mounted) return false;
      setState(() => status = 'Printer is not connected');
      showMessage('Connect XP-365B first');
    }
    return connected;
  }

  Future<void> calibrateGapSensor() async {
    if (!await ensureConnected()) return;

    try {
      setState(() {
        busy = true;
        status = 'Calibrating gap sensor...';
      });

      await printer.calibrateGapSensor();

      if (!mounted) return;
      setState(() => status = 'Gap sensor calibration command sent');
      showMessage(
        'Calibration sent. Let the printer finish feeding labels before printing.',
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => status = 'Calibration error: ${e.message ?? e.code}');
      showMessage(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'Calibration error: $e');
      showMessage(status);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> printTsplDemo() async {
    if (!await ensureConnected()) return;

    try {
      final width = readPositiveMm(widthController, 'Label width');
      final height = readPositiveMm(heightController, 'Label height');
      final gap = readGapMm();

      setState(() {
        busy = true;
        status = 'Sending TSPL label...';
      });

      await printer.printTsplRaw(
        'SIZE ${formatMm(width)} mm,${formatMm(height)} mm\r\n'
        'GAP ${formatMm(gap)} mm,0 mm\r\n'
        'SPEED 3\r\n'
        'DENSITY 7\r\n'
        'DIRECTION 1,0\r\n'
        'REFERENCE 0,0\r\n'
        'CLS\r\n'
        'TEXT 20,20,"3",0,1,1,"XP-365B TEST"\r\n'
        'TEXT 20,60,"3",0,1,1,"xprinter_flutter"\r\n'
        'PRINT 1,1\r\n',
      );

      if (!mounted) return;
      setState(
        () => status =
            'TSPL sent: ${formatMm(width)} x ${formatMm(height)} mm, gap ${formatMm(gap)} mm',
      );
      showMessage('TSPL label sent successfully');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => status = 'Media setting error: ${e.message}');
      showMessage(status);
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

  Widget mediaField(
    String label,
    TextEditingController controller,
  ) {
    return Expanded(
      child: TextField(
        controller: controller,
        enabled: !busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    loadPrinters();
  }

  @override
  void dispose() {
    widthController.dispose();
    heightController.dispose();
    gapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Label media',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the real sticker width, height and physical gap. '
                      'Wrong media values can make the XP-365B stop with the ERROR light on.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        mediaField('Width', widthController),
                        const SizedBox(width: 8),
                        mediaField('Height', heightController),
                        const SizedBox(width: 8),
                        mediaField('Gap', gapController),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy ? null : calibrateGapSensor,
                      icon: const Icon(Icons.tune),
                      label: const Text('Calibrate gap sensor'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Run calibration after changing the label roll or if the ERROR light appears after a print. '
                      'Calibration feeds labels while the sensor detects the media.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
              '2. Enter the actual label size and gap.\n'
              '3. Run Calibrate gap sensor and wait until feeding stops.\n'
              '4. Print the TSPL label test.\n'
              '5. If ESC/POS prints but TSPL does not, verify that the printer is in LABEL mode.',
            ),
          ],
        ),
      ),
    );
  }
}
