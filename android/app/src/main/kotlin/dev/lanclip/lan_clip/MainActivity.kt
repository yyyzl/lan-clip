package dev.lanclip.lan_clip

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.NetworkInterface
import java.util.Collections

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lan_clip/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "supportDirectory" -> result.success(filesDir.absolutePath)
                    "broadcastAddresses" -> {
                        try {
                            val addresses = Collections.list(NetworkInterface.getNetworkInterfaces())
                                .filter { it.isUp && !it.isLoopback }
                                .flatMap { it.interfaceAddresses }
                                .mapNotNull { it.broadcast?.hostAddress }
                                .distinct()
                            result.success(addresses)
                        } catch (_: Exception) {
                            result.success(emptyList<String>())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
