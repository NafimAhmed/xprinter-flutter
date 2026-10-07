## 0.1.1

- Added TSPL gap sensor calibration with `calibrateGapSensor()`.
- Updated the XP-365B example with configurable label width, height, and gap.
- Simplified the TSPL diagnostic label to avoid unrelated QR/barcode variables while troubleshooting media errors.
- Added guidance for post-print ERROR light issues caused by label/gap sensor mismatch.

## 0.1.0

- Initial Android release.
- Direct Bluetooth SPP printing.
- Bluetooth paired-device listing and active discovery.
- Direct TCP/IP printing with port 9100 default.
- Direct USB bulk printing with Android USB permission handling.
- Structured TSPL labels with text, barcode, QR code, box, bar, copies, label size and gap controls.
- Raw TSPL, ZPL, CPCL and arbitrary byte command support.
- Basic ESC/POS text and QR helpers.
- Connection status and connection event stream.
- Android 12+ Bluetooth support using SCAN/CONNECT permissions without location permission.
- No external XPrinter app and no vendor SDK binary dependency.
