package com.nafimahmed.xprinter_flutter

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import java.util.concurrent.Executors

class XprinterFlutterPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var scanEvents: EventChannel
    private lateinit var connectionEvents: EventChannel

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null

    private var scanSink: EventChannel.EventSink? = null
    private var connectionSink: EventChannel.EventSink? = null
    private var scanReceiver: BroadcastReceiver? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var transport: Transport? = null
    private var connectionType: String? = null
    private var connectionInfo: String? = null

    private val bluetooth: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private val usb: UsbManager
        get() = context.getSystemService(Context.USB_SERVICE) as UsbManager

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "xprinter_flutter/methods")
        methods.setMethodCallHandler(this)

        scanEvents = EventChannel(binding.binaryMessenger, "xprinter_flutter/bluetooth_scan")
        scanEvents.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                scanSink = events
            }
            override fun onCancel(arguments: Any?) {
                scanSink = null
                stopScan()
            }
        })

        connectionEvents = EventChannel(binding.binaryMessenger, "xprinter_flutter/connection_events")
        connectionEvents.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                connectionSink = events
            }
            override fun onCancel(arguments: Any?) {
                connectionSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopScan()
        closeTransport()
        executor.shutdownNow()
        methods.setMethodCallHandler(null)
        scanEvents.setStreamHandler(null)
        connectionEvents.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "platformVersion" -> result.success("Android " + Build.VERSION.RELEASE)
                "requestBluetoothPermissions" -> requestBluetoothPermissions(result)
                "getBondedBluetoothDevices" -> result.success(bondedDevices())
                "startBluetoothScan" -> result.success(startScan())
                "stopBluetoothScan" -> { stopScan(); result.success(null) }
                "getUsbDevices" -> result.success(usbDevices())
                "getSerialPorts" -> result.success(emptyList<String>())
                "connectBluetooth" -> connectBluetooth(
                    call.argument<String>("address") ?: return result.error("bad_args", "address is required", null),
                    result
                )
                "connectNetwork" -> connectNetwork(
                    call.argument<String>("host") ?: return result.error("bad_args", "host is required", null),
                    call.argument<Int>("port") ?: 9100,
                    result
                )
                "connectUsb" -> connectUsb(
                    call.argument<String>("path") ?: return result.error("bad_args", "path is required", null),
                    result
                )
                "connectSerial" -> result.error("unsupported", "Serial transport is not implemented yet", null)
                "disconnect" -> { closeTransport(); emit(false, 0, null, "Disconnected"); result.success(null) }
                "isConnected" -> result.success(transport?.isConnected == true)
                "getConnectionInfo" -> result.success(mapOf(
                    "connected" to (transport?.isConnected == true),
                    "type" to connectionType,
                    "info" to connectionInfo
                ))
                "printRaw" -> {
                    val data = call.argument<ByteArray>("data")
                        ?: return result.error("bad_args", "data is required", null)
                    writeAsync(data, result)
                }
                "printTsplLabel" -> writeAsync(buildTspl(call), result)
                "testPrint" -> {
                    val width = call.argument<Number>("widthMm")?.toDouble() ?: 60.0
                    val height = call.argument<Number>("heightMm")?.toDouble() ?: 40.0
                    val cmd = "SIZE " + fmt(width) + " mm," + fmt(height) + " mm\r\n" +
                        "GAP 2 mm,0 mm\r\nDENSITY 8\r\nCLS\r\n" +
                        "TEXT 20,20,\"3\",0,1,1,\"xprinter_flutter\"\r\n" +
                        "QRCODE 20,70,M,5,A,0,\"https://github.com/NafimAhmed/xprinter-flutter\"\r\n" +
                        "PRINT 1,1\r\n"
                    writeAsync(cmd.toByteArray(Charsets.UTF_8), result)
                }
                "printPosText" -> writeAsync(
                    escPosText(
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("feedLines") ?: 1,
                        call.argument<Boolean>("cut") == true
                    ),
                    result
                )
                "printPosQr" -> writeAsync(
                    escPosQr(
                        call.argument<String>("data") ?: "",
                        call.argument<Int>("feedLines") ?: 1,
                        call.argument<Boolean>("cut") == true
                    ),
                    result
                )
                "getTsplStatus", "getSerialNumber", "getFirmwareVersion" ->
                    result.error("unsupported", "Vendor-specific query APIs are not exposed in the direct transport build yet", null)
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: Exception) {
            result.error("xprinter_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun connectBluetooth(address: String, result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("permission_denied", "Bluetooth permissions are not granted", null)
            return
        }
        val adapter = bluetooth ?: return result.error("bluetooth_unavailable", "Bluetooth is unavailable", null)
        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is disabled", null)
            return
        }

        executor.execute {
            try {
                closeTransport()
                adapter.cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                socket.connect()
                transport = BluetoothTransport(socket)
                connectionType = "bluetooth"
                connectionInfo = address
                main.post { emit(true, 1, address, "Connected"); result.success(null) }
            } catch (e: Exception) {
                closeTransport()
                main.post {
                    emit(false, -1, address, e.message)
                    result.error("connect_failed", e.message ?: "Bluetooth connection failed", null)
                }
            }
        }
    }

    private fun connectNetwork(host: String, port: Int, result: MethodChannel.Result) {
        executor.execute {
            try {
                closeTransport()
                val socket = Socket()
                socket.connect(InetSocketAddress(host, port), 5000)
                socket.tcpNoDelay = true
                transport = TcpTransport(socket)
                connectionType = "ethernet"
                connectionInfo = host + "," + port
                main.post { emit(true, 1, connectionInfo, "Connected"); result.success(null) }
            } catch (e: Exception) {
                closeTransport()
                main.post {
                    emit(false, -1, host + "," + port, e.message)
                    result.error("connect_failed", e.message ?: "Network connection failed", null)
                }
            }
        }
    }

    private fun connectUsb(path: String, result: MethodChannel.Result) {
        val device = usb.deviceList.values.firstOrNull { it.deviceName == path }
            ?: return result.error("usb_not_found", "USB printer not found: " + path, null)

        if (usb.hasPermission(device)) {
            openUsb(device, result)
            return
        }

        val action = context.packageName + ".XPRINTER_USB_PERMISSION"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (intent?.action != action) return
                try { context.unregisterReceiver(this) } catch (_: Exception) {}

                val received = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                }

                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                if (granted && received != null) {
                    openUsb(received, result)
                } else {
                    result.error("permission_denied", "USB permission was denied", null)
                }
            }
        }

        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(receiver, filter)
        }

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val pending = PendingIntent.getBroadcast(context, 0, Intent(action), flags)
        usb.requestPermission(device, pending)
    }

    private fun openUsb(device: UsbDevice, result: MethodChannel.Result) {
        executor.execute {
            try {
                closeTransport()
                val pair = findUsbOut(device)
                    ?: throw IllegalStateException("No USB bulk OUT endpoint found")
                val conn = usb.openDevice(device)
                    ?: throw IllegalStateException("Unable to open USB printer")
                if (!conn.claimInterface(pair.first, true)) {
                    conn.close()
                    throw IllegalStateException("Unable to claim USB interface")
                }
                transport = UsbTransport(conn, pair.first, pair.second)
                connectionType = "usb"
                connectionInfo = device.deviceName
                main.post { emit(true, 1, device.deviceName, "Connected"); result.success(null) }
            } catch (e: Exception) {
                closeTransport()
                main.post {
                    emit(false, -1, device.deviceName, e.message)
                    result.error("connect_failed", e.message ?: "USB connection failed", null)
                }
            }
        }
    }

    private fun writeAsync(data: ByteArray, result: MethodChannel.Result) {
        val t = transport?.takeIf { it.isConnected }
            ?: return result.error("not_connected", "No printer is connected", null)

        executor.execute {
            try {
                t.write(data)
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post {
                    emit(false, -2, connectionInfo, e.message)
                    result.error("write_failed", e.message ?: "Printer write failed", null)
                }
            }
        }
    }

    private fun buildTspl(call: MethodCall): ByteArray {
        val width = call.argument<Number>("widthMm")?.toDouble() ?: 60.0
        val height = call.argument<Number>("heightMm")?.toDouble() ?: 40.0
        val gap = call.argument<Number>("gapMm")?.toDouble() ?: 2.0
        val gapOffset = call.argument<Number>("gapOffsetMm")?.toDouble() ?: 0.0
        val speed = call.argument<Number>("speed")?.toDouble() ?: 5.0
        val density = call.argument<Int>("density") ?: 8
        val direction = call.argument<Int>("direction") ?: 0
        val referenceX = call.argument<Int>("referenceX") ?: 0
        val referenceY = call.argument<Int>("referenceY") ?: 0
        val copies = (call.argument<Int>("copies") ?: 1).coerceAtLeast(1)
        val clear = call.argument<Boolean>("clearBeforePrint") ?: true
        val offset = call.argument<Number>("offsetMm")?.toDouble()
        val elements = call.argument<List<Map<String, Any?>>>("elements") ?: emptyList()

        val out = StringBuilder()
        out.append("SIZE ").append(fmt(width)).append(" mm,").append(fmt(height)).append(" mm\r\n")
        out.append("GAP ").append(fmt(gap)).append(" mm,").append(fmt(gapOffset)).append(" mm\r\n")
        if (offset != null) out.append("OFFSET ").append(fmt(offset)).append(" mm\r\n")
        out.append("SPEED ").append(fmt(speed)).append("\r\n")
        out.append("DENSITY ").append(density).append("\r\n")
        out.append("DIRECTION ").append(direction).append("\r\n")
        out.append("REFERENCE ").append(referenceX).append(",").append(referenceY).append("\r\n")
        if (clear) out.append("CLS\r\n")

        for (e in elements) {
            when (e["type"] as? String) {
                "text" -> out.append("TEXT ")
                    .append(iv(e, "x")).append(",").append(iv(e, "y")).append(",")
                    .append(q(sv(e, "font", "3"))).append(",")
                    .append(iv(e, "rotation", 0)).append(",")
                    .append(iv(e, "xScale", 1)).append(",")
                    .append(iv(e, "yScale", 1)).append(",")
                    .append(q(sv(e, "text"))).append("\r\n")

                "barcode" -> out.append("BARCODE ")
                    .append(iv(e, "x")).append(",").append(iv(e, "y")).append(",")
                    .append(q(sv(e, "barcodeType", "128"))).append(",")
                    .append(iv(e, "height", 80)).append(",")
                    .append(iv(e, "readable", 2)).append(",")
                    .append(iv(e, "rotation", 0)).append(",")
                    .append(iv(e, "narrow", 2)).append(",")
                    .append(iv(e, "wide", 2)).append(",")
                    .append(q(sv(e, "data"))).append("\r\n")

                "qrcode" -> out.append("QRCODE ")
                    .append(iv(e, "x")).append(",").append(iv(e, "y")).append(",")
                    .append(sv(e, "errorCorrection", "M")).append(",")
                    .append(iv(e, "cellWidth", 5)).append(",")
                    .append(sv(e, "mode", "A")).append(",")
                    .append(iv(e, "rotation", 0)).append(",")
                    .append(q(sv(e, "data"))).append("\r\n")

                "box" -> out.append("BOX ")
                    .append(iv(e, "x")).append(",").append(iv(e, "y")).append(",")
                    .append(iv(e, "xEnd")).append(",").append(iv(e, "yEnd")).append(",")
                    .append(iv(e, "thickness", 2)).append("\r\n")

                "bar" -> out.append("BAR ")
                    .append(iv(e, "x")).append(",").append(iv(e, "y")).append(",")
                    .append(iv(e, "width")).append(",").append(iv(e, "height")).append("\r\n")
            }
        }

        out.append("PRINT 1,").append(copies).append("\r\n")
        return out.toString().toByteArray(Charsets.UTF_8)
    }

    private fun escPosText(text: String, feeds: Int, cut: Boolean): ByteArray =
        ByteArrayOutputStream().apply {
            write(byteArrayOf(0x1B, 0x40))
            write(text.toByteArray(Charsets.UTF_8))
            repeat(feeds.coerceAtLeast(0)) { write('\n'.code) }
            if (cut) write(byteArrayOf(0x1D, 0x56, 0x42, 0x00))
        }.toByteArray()

    private fun escPosQr(data: String, feeds: Int, cut: Boolean): ByteArray {
        val body = data.toByteArray(Charsets.UTF_8)
        val len = body.size + 3
        return ByteArrayOutputStream().apply {
            write(byteArrayOf(0x1B, 0x40))
            write(byteArrayOf(0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00))
            write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05))
            write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31))
            write(byteArrayOf(0x1D, 0x28, 0x6B, (len and 0xFF).toByte(), ((len shr 8) and 0xFF).toByte(), 0x31, 0x50, 0x30))
            write(body)
            write(byteArrayOf(0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30))
            repeat(feeds.coerceAtLeast(0)) { write('\n'.code) }
            if (cut) write(byteArrayOf(0x1D, 0x56, 0x42, 0x00))
        }.toByteArray()
    }

    private fun bondedDevices(): List<Map<String, Any?>> {
        if (!hasBluetoothPermissions()) throw SecurityException("Bluetooth permissions are not granted")
        return bluetooth?.bondedDevices?.map { deviceMap(it, true, null) } ?: emptyList()
    }

    private fun startScan(): Boolean {
        if (!hasBluetoothPermissions()) throw SecurityException("Bluetooth permissions are not granted")
        val adapter = bluetooth ?: throw IllegalStateException("Bluetooth is unavailable")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is disabled")

        stopScan()
        adapter.bondedDevices.forEach { scanSink?.success(deviceMap(it, true, null)) }

        scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val d = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        if (d != null) {
                            val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
                            scanSink?.success(deviceMap(d, d.bondState == BluetoothDevice.BOND_BONDED, rssi))
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED ->
                        scanSink?.success(mapOf("event" to "finished"))
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }

        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(scanReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(scanReceiver, filter)
        }

        if (adapter.isDiscovering) adapter.cancelDiscovery()
        return adapter.startDiscovery()
    }

    private fun stopScan() {
        try {
            if (hasBluetoothPermissions()) bluetooth?.takeIf { it.isDiscovering }?.cancelDiscovery()
        } catch (_: Exception) {}
        scanReceiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        scanReceiver = null
    }

    private fun hasBluetoothPermissions(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        } else true

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (hasBluetoothPermissions()) {
            result.success(true)
            return
        }

        val a = activity ?: return result.error("no_activity", "Activity is required", null)
        if (permissionResult != null) {
            result.error("request_in_progress", "Permission request already in progress", null)
            return
        }

        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        permissionResult = result
        a.requestPermissions(permissions, REQUEST_BT)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_BT) return false
        val ok = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(ok)
        permissionResult = null
        return true
    }

    private fun usbDevices(): List<String> =
        usb.deviceList.values.filter { findUsbOut(it) != null }.map { it.deviceName }

    private fun findUsbOut(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    ep.direction == UsbConstants.USB_DIR_OUT) {
                    return intf to ep
                }
            }
        }
        return null
    }

    private fun deviceMap(device: BluetoothDevice, bonded: Boolean, rssi: Int?) =
        mapOf(
            "event" to "device",
            "name" to (device.name ?: "Unknown"),
            "address" to device.address,
            "bonded" to bonded,
            "rssi" to rssi
        )

    private fun emit(connected: Boolean, code: Int, info: String?, message: String?) {
        connectionSink?.success(mapOf(
            "code" to code,
            "connected" to connected,
            "info" to info,
            "message" to message
        ))
    }

    private fun closeTransport() {
        try { transport?.close() } catch (_: Exception) {}
        transport = null
        connectionType = null
        connectionInfo = null
    }

    private fun iv(m: Map<String, Any?>, key: String, def: Int = 0) =
        (m[key] as? Number)?.toInt() ?: def

    private fun sv(m: Map<String, Any?>, key: String, def: String = "") =
        m[key]?.toString() ?: def

    private fun q(value: String) =
        "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\r", " ").replace("\n", " ") + "\""

    private fun fmt(value: Double) =
        if (value % 1.0 == 0.0) value.toInt().toString() else value.toString()

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    private interface Transport : Closeable {
        val isConnected: Boolean
        fun write(data: ByteArray)
    }

    private class BluetoothTransport(private val socket: BluetoothSocket) : Transport {
        private val out: OutputStream = socket.outputStream
        override val isConnected: Boolean get() = socket.isConnected
        override fun write(data: ByteArray) { out.write(data); out.flush() }
        override fun close() { try { out.close() } catch (_: Exception) {}; socket.close() }
    }

    private class TcpTransport(private val socket: Socket) : Transport {
        private val out: OutputStream = socket.getOutputStream()
        override val isConnected: Boolean get() = socket.isConnected && !socket.isClosed
        override fun write(data: ByteArray) { out.write(data); out.flush() }
        override fun close() { try { out.close() } catch (_: Exception) {}; socket.close() }
    }

    private class UsbTransport(
        private val conn: UsbDeviceConnection,
        private val intf: UsbInterface,
        private val ep: UsbEndpoint
    ) : Transport {
        override val isConnected: Boolean get() = true
        override fun write(data: ByteArray) {
            var offset = 0
            while (offset < data.size) {
                val n = minOf(16384, data.size - offset)
                val chunk = data.copyOfRange(offset, offset + n)
                val written = conn.bulkTransfer(ep, chunk, chunk.size, 5000)
                if (written <= 0) throw IllegalStateException("USB bulk transfer failed")
                offset += written
            }
        }
        override fun close() {
            try { conn.releaseInterface(intf) } catch (_: Exception) {}
            conn.close()
        }
    }

    companion object {
        private const val REQUEST_BT = 5108
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
