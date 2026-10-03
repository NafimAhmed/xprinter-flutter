package com.nafimahmed.xprinter_flutter

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSPrinter
import net.posprinter.TSPLPrinter
import net.posprinter.model.AlgorithmType
import java.util.concurrent.atomic.AtomicBoolean

class XprinterFlutterPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var scanChannel: EventChannel
    private lateinit var connectionChannel: EventChannel

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var currentConnection: IDeviceConnection? = null
    private var connectionType: String? = null
    private var connectionInfo: String? = null

    private var scanSink: EventChannel.EventSink? = null
    private var connectionSink: EventChannel.EventSink? = null
    private var scanReceiver: BroadcastReceiver? = null
    private var permissionResult: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private val bluetoothAdapter: BluetoothAdapter?
        get() = (applicationContext.getSystemService(Context.BLUETOOTH_SERVICE)
                as? BluetoothManager)?.adapter

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        POSConnect.init(applicationContext)

        methodChannel =
            MethodChannel(binding.binaryMessenger, "xprinter_flutter/methods")
        methodChannel.setMethodCallHandler(this)

        scanChannel =
            EventChannel(binding.binaryMessenger, "xprinter_flutter/bluetooth_scan")
        scanChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                scanSink = events
            }

            override fun onCancel(arguments: Any?) {
                scanSink = null
                stopBluetoothScanInternal()
            }
        })

        connectionChannel =
            EventChannel(binding.binaryMessenger, "xprinter_flutter/connection_events")
        connectionChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                connectionSink = events
            }

            override fun onCancel(arguments: Any?) {
                connectionSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopBluetoothScanInternal()
        currentConnection?.close()
        currentConnection = null
        methodChannel.setMethodCallHandler(null)
        scanChannel.setStreamHandler(null)
        connectionChannel.setStreamHandler(null)
        POSConnect.exit()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "platformVersion" ->
                    result.success("Android ${Build.VERSION.RELEASE}")

                "requestBluetoothPermissions" ->
                    requestBluetoothPermissions(result)

                "getBondedBluetoothDevices" ->
                    result.success(getBondedDevices())

                "startBluetoothScan" ->
                    result.success(startBluetoothScanInternal())

                "stopBluetoothScan" -> {
                    stopBluetoothScanInternal()
                    result.success(null)
                }

                "getUsbDevices" ->
                    result.success(POSConnect.getUsbDevices(applicationContext))

                "getSerialPorts" ->
                    result.success(POSConnect.getSerialPort())

                "connectBluetooth" -> {
                    val address = call.argument<String>("address")
                        ?: return result.error(
                            "bad_args",
                            "address is required",
                            null,
                        )
                    connect(
                        POSConnect.DEVICE_TYPE_BLUETOOTH,
                        address,
                        "bluetooth",
                        result,
                    )
                }

                "connectNetwork" -> {
                    val host = call.argument<String>("host")
                        ?: return result.error(
                            "bad_args",
                            "host is required",
                            null,
                        )
                    val port = call.argument<Int>("port")
                    val info = if (port == null) host else "$host,$port"
                    connect(
                        POSConnect.DEVICE_TYPE_ETHERNET,
                        info,
                        "ethernet",
                        result,
                    )
                }

                "connectUsb" -> {
                    val path = call.argument<String>("path")
                        ?: return result.error(
                            "bad_args",
                            "path is required",
                            null,
                        )
                    connect(
                        POSConnect.DEVICE_TYPE_USB,
                        path,
                        "usb",
                        result,
                    )
                }

                "connectSerial" -> {
                    val port = call.argument<String>("port")
                        ?: return result.error(
                            "bad_args",
                            "port is required",
                            null,
                        )
                    val baudRate = call.argument<Int>("baudRate") ?: 9600
                    connect(
                        POSConnect.DEVICE_TYPE_SERIAL,
                        "$port,$baudRate",
                        "serial",
                        result,
                    )
                }

                "disconnect" -> {
                    currentConnection?.close()
                    currentConnection = null
                    connectionType = null
                    connectionInfo = null
                    result.success(null)
                }

                "isConnected" ->
                    result.success(currentConnection?.isConnect == true)

                "getConnectionInfo" ->
                    result.success(
                        mapOf(
                            "connected" to (currentConnection?.isConnect == true),
                            "type" to connectionType,
                            "info" to connectionInfo,
                        )
                    )

                "printRaw" -> {
                    val data = call.argument<ByteArray>("data")
                        ?: return result.error(
                            "bad_args",
                            "data is required",
                            null,
                        )
                    requireConnection().sendData(data)
                    result.success(null)
                }

                "printTsplLabel" ->
                    printTsplLabel(call, result)

                "testPrint" ->
                    testPrint(call, result)

                "getTsplStatus" ->
                    getTsplStatus(call, result)

                "getSerialNumber" ->
                    getSerialNumber(result)

                "getFirmwareVersion" ->
                    getFirmwareVersion(result)

                "printPosText" ->
                    printPosText(call, result)

                "printPosQr" ->
                    printPosQr(call, result)

                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("not_connected", e.message, null)
        } catch (e: Exception) {
            result.error(
                "xprinter_error",
                e.message ?: e.javaClass.simpleName,
                null,
            )
        }
    }

    private fun requireConnection(): IDeviceConnection =
        currentConnection?.takeIf { it.isConnect }
            ?: throw IllegalStateException("No XPrinter is connected")

    private fun connect(
        deviceType: Int,
        info: String,
        typeName: String,
        result: MethodChannel.Result,
    ) {
        currentConnection?.close()

        val connection = POSConnect.createDevice(deviceType)
        currentConnection = connection
        connectionType = typeName
        connectionInfo = info

        val completed = AtomicBoolean(false)

        connection.connect(info) { code, connectInfo, message ->
            val connected = code == POSConnect.CONNECT_SUCCESS

            if (connected) {
                connectionInfo = connectInfo ?: info
            }

            if (code == POSConnect.CONNECT_INTERRUPT ||
                code == POSConnect.CONNECT_FAIL
            ) {
                if (currentConnection === connection) {
                    connectionType = null
                    connectionInfo = null
                }
            }

            mainHandler.post {
                connectionSink?.success(
                    mapOf(
                        "code" to code,
                        "connected" to connected,
                        "info" to connectInfo,
                        "message" to message,
                    )
                )

                when (code) {
                    POSConnect.CONNECT_SUCCESS -> {
                        if (completed.compareAndSet(false, true)) {
                            result.success(null)
                        }
                    }

                    POSConnect.CONNECT_FAIL,
                    POSConnect.CONNECT_INTERRUPT -> {
                        if (completed.compareAndSet(false, true)) {
                            result.error(
                                "connect_failed",
                                message ?: "Unable to connect to printer",
                                code,
                            )
                        }
                    }
                }
            }
        }
    }

    private fun getBondedDevices(): List<Map<String, Any?>> {
        if (!hasBluetoothPermissions()) {
            throw SecurityException("Bluetooth permissions are not granted")
        }

        return bluetoothAdapter
            ?.bondedDevices
            ?.map { device -> deviceMap(device, true, null) }
            ?: emptyList()
    }

    private fun deviceMap(
        device: BluetoothDevice,
        bonded: Boolean,
        rssi: Int?,
    ): Map<String, Any?> =
        mapOf(
            "event" to "device",
            "name" to (device.name ?: "Unknown"),
            "address" to device.address,
            "bonded" to bonded,
            "rssi" to rssi,
        )

    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applicationContext.checkSelfPermission(
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED &&
                applicationContext.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            applicationContext.checkSelfPermission(
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (hasBluetoothPermissions()) {
            result.success(true)
            return
        }

        val currentActivity = activity ?: run {
            result.error(
                "no_activity",
                "An Android Activity is required to request Bluetooth permissions",
                null,
            )
            return
        }

        if (permissionResult != null) {
            result.error(
                "request_in_progress",
                "A Bluetooth permission request is already in progress",
                null,
            )
            return
        }

        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                )

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

            else -> emptyArray()
        }

        if (permissions.isEmpty()) {
            result.success(true)
            return
        }

        permissionResult = result
        currentActivity.requestPermissions(
            permissions,
            REQUEST_BLUETOOTH_PERMISSIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_BLUETOOTH_PERMISSIONS) {
            return false
        }

        val granted =
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        permissionResult?.success(granted)
        permissionResult = null
        return true
    }

    private fun startBluetoothScanInternal(): Boolean {
        if (!hasBluetoothPermissions()) {
            throw SecurityException("Bluetooth permissions are not granted")
        }

        val adapter =
            bluetoothAdapter
                ?: throw IllegalStateException(
                    "Bluetooth is not supported on this device"
                )

        if (!adapter.isEnabled) {
            throw IllegalStateException("Bluetooth is disabled")
        }

        stopBluetoothScanInternal()

        adapter.bondedDevices.forEach {
            scanSink?.success(deviceMap(it, true, null))
        }

        scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device =
                            if (Build.VERSION.SDK_INT >= 33) {
                                intent.getParcelableExtra(
                                    BluetoothDevice.EXTRA_DEVICE,
                                    BluetoothDevice::class.java,
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra(
                                    BluetoothDevice.EXTRA_DEVICE
                                )
                            }

                        val rssi =
                            intent.getShortExtra(
                                BluetoothDevice.EXTRA_RSSI,
                                Short.MIN_VALUE,
                            ).toInt()

                        if (device != null) {
                            scanSink?.success(
                                deviceMap(
                                    device,
                                    device.bondState ==
                                        BluetoothDevice.BOND_BONDED,
                                    rssi,
                                )
                            )
                        }
                    }

                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED ->
                        scanSink?.success(
                            mapOf("event" to "finished")
                        )
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }

        if (Build.VERSION.SDK_INT >= 33) {
            applicationContext.registerReceiver(
                scanReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            applicationContext.registerReceiver(
                scanReceiver,
                filter,
            )
        }

        if (adapter.isDiscovering) {
            adapter.cancelDiscovery()
        }

        return adapter.startDiscovery()
    }

    private fun stopBluetoothScanInternal() {
        try {
            if (hasBluetoothPermissions()) {
                bluetoothAdapter
                    ?.takeIf { it.isDiscovering }
                    ?.cancelDiscovery()
            }
        } catch (_: Exception) {
        }

        scanReceiver?.let {
            try {
                applicationContext.unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }

        scanReceiver = null
    }

    private fun printTsplLabel(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val connection = requireConnection()

        val width =
            call.argument<Number>("widthMm")?.toDouble() ?: 60.0
        val height =
            call.argument<Number>("heightMm")?.toDouble() ?: 40.0
        val gap =
            call.argument<Number>("gapMm")?.toDouble() ?: 2.0
        val gapOffset =
            call.argument<Number>("gapOffsetMm")?.toDouble() ?: 0.0
        val offset =
            call.argument<Number>("offsetMm")?.toDouble()
        val speed =
            call.argument<Number>("speed")?.toDouble() ?: 5.0
        val density =
            call.argument<Int>("density") ?: 8
        val direction =
            call.argument<Int>("direction") ?: 0
        val referenceX =
            call.argument<Int>("referenceX") ?: 0
        val referenceY =
            call.argument<Int>("referenceY") ?: 0
        val copies =
            (call.argument<Int>("copies") ?: 1).coerceAtLeast(1)
        val clearBeforePrint =
            call.argument<Boolean>("clearBeforePrint") ?: true
        val elements =
            call.argument<List<Map<String, Any?>>>("elements")
                ?: emptyList()

        var printer =
            TSPLPrinter(connection)
                .sizeMm(width, height)
                .gapMm(gap, gapOffset)
                .speed(speed)
                .density(density)
                .direction(direction)
                .reference(referenceX, referenceY)

        if (offset != null) {
            printer = printer.offsetMm(offset)
        }

        if (clearBeforePrint) {
            printer = printer.cls()
        }

        for (element in elements) {
            when (element["type"] as? String) {
                "text" ->
                    printer.text(
                        intValue(element, "x"),
                        intValue(element, "y"),
                        stringValue(element, "font", "3"),
                        intValue(element, "rotation", 0),
                        intValue(element, "xScale", 1),
                        intValue(element, "yScale", 1),
                        stringValue(element, "text"),
                    )

                "barcode" ->
                    printer.barcode(
                        intValue(element, "x"),
                        intValue(element, "y"),
                        stringValue(element, "barcodeType", "128"),
                        intValue(element, "height", 80),
                        intValue(element, "readable", 2),
                        intValue(element, "rotation", 0),
                        intValue(element, "narrow", 2),
                        intValue(element, "wide", 2),
                        stringValue(element, "data"),
                    )

                "qrcode" ->
                    printer.qrcode(
                        intValue(element, "x"),
                        intValue(element, "y"),
                        stringValue(element, "errorCorrection", "M"),
                        intValue(element, "cellWidth", 5),
                        stringValue(element, "mode", "A"),
                        intValue(element, "rotation", 0),
                        stringValue(element, "data"),
                    )

                "box" ->
                    printer.box(
                        intValue(element, "x"),
                        intValue(element, "y"),
                        intValue(element, "xEnd"),
                        intValue(element, "yEnd"),
                        intValue(element, "thickness", 2),
                    )

                "bar" ->
                    printer.bar(
                        intValue(element, "x"),
                        intValue(element, "y"),
                        intValue(element, "width"),
                        intValue(element, "height"),
                    )

                "image" -> {
                    val bytes =
                        Base64.decode(
                            stringValue(element, "base64"),
                            Base64.DEFAULT,
                        )
                    val bitmap =
                        BitmapFactory.decodeByteArray(
                            bytes,
                            0,
                            bytes.size,
                        )
                            ?: throw IllegalArgumentException(
                                "Invalid image data"
                            )

                    printer.bitmap(
                        intValue(element, "x"),
                        intValue(element, "y"),
                        intValue(element, "mode", 0),
                        intValue(element, "width", 576),
                        bitmap,
                        algorithm(element["algorithm"] as? String),
                    )
                }
            }
        }

        printer.print(copies)
        result.success(null)
    }

    private fun testPrint(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val width =
            call.argument<Number>("widthMm")?.toDouble() ?: 60.0
        val height =
            call.argument<Number>("heightMm")?.toDouble() ?: 40.0

        TSPLPrinter(requireConnection())
            .sizeMm(width, height)
            .gapMm(2.0, 0.0)
            .density(8)
            .cls()
            .text(
                20,
                20,
                "3",
                0,
                1,
                1,
                "xprinter_flutter",
            )
            .qrcode(
                20,
                70,
                "M",
                5,
                "A",
                0,
                "https://github.com/NafimAhmed/xprinter-flutter",
            )
            .print(1)

        result.success(null)
    }

    private fun getTsplStatus(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val timeout =
            call.argument<Int>("timeoutMs") ?: 1500

        TSPLPrinter(requireConnection())
            .printerStatus(timeout) { code ->
                mainHandler.post {
                    result.success(code)
                }
            }
    }

    private fun getSerialNumber(
        result: MethodChannel.Result,
    ) {
        TSPLPrinter(requireConnection())
            .getSerialNumber { value ->
                mainHandler.post {
                    result.success(value)
                }
            }
    }

    private fun getFirmwareVersion(
        result: MethodChannel.Result,
    ) {
        TSPLPrinter(requireConnection())
            .getFirmwareVersion { value ->
                mainHandler.post {
                    result.success(value)
                }
            }
    }

    private fun printPosText(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val printer =
            POSPrinter(requireConnection())
                .initializePrinter()
                .printString(
                    call.argument<String>("text") ?: ""
                )

        val feedLines =
            call.argument<Int>("feedLines") ?: 1

        if (feedLines > 0) {
            printer.feedLine(feedLines)
        }

        if (call.argument<Boolean>("cut") == true) {
            printer.cutHalfAndFeed(1)
        }

        result.success(null)
    }

    private fun printPosQr(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val printer =
            POSPrinter(requireConnection())
                .initializePrinter()
                .printQRCode(
                    call.argument<String>("data") ?: ""
                )

        val feedLines =
            call.argument<Int>("feedLines") ?: 1

        if (feedLines > 0) {
            printer.feedLine(feedLines)
        }

        if (call.argument<Boolean>("cut") == true) {
            printer.cutHalfAndFeed(1)
        }

        result.success(null)
    }

    private fun algorithm(value: String?): AlgorithmType =
        when (value?.lowercase()) {
            "dithering" -> AlgorithmType.Dithering
            "diffusion" -> AlgorithmType.Diffusion
            "halftone" -> AlgorithmType.Halftone
            "none" -> AlgorithmType.None
            else -> AlgorithmType.Threshold
        }

    private fun intValue(
        map: Map<String, Any?>,
        key: String,
        default: Int = 0,
    ): Int =
        (map[key] as? Number)?.toInt() ?: default

    private fun stringValue(
        map: Map<String, Any?>,
        key: String,
        default: String = "",
    ): String =
        map[key]?.toString() ?: default

    override fun onAttachedToActivity(
        binding: ActivityPluginBinding,
    ) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(
        binding: ActivityPluginBinding,
    ) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding
            ?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    companion object {
        private const val REQUEST_BLUETOOTH_PERMISSIONS = 5108
    }
}
