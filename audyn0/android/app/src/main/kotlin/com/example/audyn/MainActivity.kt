package com.example.audyn

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    private val CHANNEL = "libtorrent_wrapper"
    private val libtorrentWrapper = LibtorrentWrapper()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersion" -> {
                    try {
                        val version = libtorrentWrapper.getVersion()
                        result.success(version)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "addTorrent" -> {
                    val args = call.arguments
                    android.util.Log.d("MethodChannel", "addTorrent args: $args, type: ${args?.javaClass}")

                    if (args !is Map<*, *>) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }

                    val filePath = args["filePath"] as? String
                    val savePath = args["savePath"] as? String
                    android.util.Log.d("MethodChannel", "filePath: $filePath, savePath: $savePath")

                    if (filePath.isNullOrEmpty() || savePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "Missing or empty filePath or savePath", null)
                        return@setMethodCallHandler
                    }

                    val seedMode = args["seedMode"] as? Boolean ?: false
                    val announce = args["announce"] as? Boolean ?: false
                    val enableDHT = args["enableDHT"] as? Boolean ?: false
                    val enableLSD = args["enableLSD"] as? Boolean ?: true
                    val enableUTP = args["enableUTP"] as? Boolean ?: true
                    val enableTrackers = args["enableTrackers"] as? Boolean ?: false
                    val enablePeerExchange = args["enablePeerExchange"] as? Boolean ?: true

                    try {
                        val success = libtorrentWrapper.addTorrent(
                            filePath,
                            savePath,
                            seedMode,
                            announce,
                            enableDHT,
                            enableLSD,
                            enableUTP,
                            enableTrackers,
                            enablePeerExchange
                        )
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }


                "createTorrent" -> {
                    val args = call.arguments
                    if (args !is Map<*, *>) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }

                    val filePath = args["filePath"] as? String
                    val outputPath = args["outputPath"] as? String
                    val trackersList = args["trackers"] as? List<*>
                    val trackersArray = trackersList?.filterIsInstance<String>()?.toTypedArray()

                    if (filePath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "Missing or empty filePath or outputPath", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val success = libtorrentWrapper.createTorrent(filePath, outputPath, trackersArray)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "getTorrentStats" -> {
                    try {
                        val statsJson = libtorrentWrapper.getTorrentStats()
                        result.success(statsJson)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "getInfoHash" -> {
                    val filePath = call.arguments
                    if (filePath !is String || filePath.isEmpty()) {
                        result.error("ARG_ERROR", "Expected non-empty filePath string", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val hash = libtorrentWrapper.getInfoHash(filePath)
                        if (hash.isNullOrEmpty()) {
                            result.error("HASH_ERROR", "Failed to extract info hash", null)
                        } else {
                            result.success(hash)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "getSwarmInfo" -> {
                    val infoHash = call.arguments
                    if (infoHash !is String || infoHash.isEmpty()) {
                        result.error("ARG_ERROR", "Expected non-empty infoHash string", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val swarmInfo = libtorrentWrapper.getSwarmInfo(infoHash)
                        result.success(swarmInfo)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "removeTorrentByInfoHash" -> {
                    val infoHash = when (val args = call.arguments) {
                        is String -> args
                        is Map<*, *> -> args["infoHash"] as? String
                        else -> null
                    }
                    if (infoHash.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "infoHash is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val success = libtorrentWrapper.removeTorrentByInfoHash(infoHash)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "cleanupSession" -> {
                    try {
                        libtorrentWrapper.cleanupSession()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "getTorrentSavePath" -> {
                    val rawArgs = call.arguments
                    android.util.Log.d("MethodChannel", "getTorrentSavePath args: $rawArgs, type: ${rawArgs?.javaClass}")

                    val infoHash: String? = when (rawArgs) {
                        is String -> rawArgs
                        is Map<*, *> -> rawArgs["infoHash"] as? String
                        else -> null
                    }

                    if (infoHash.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "infoHash is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val savePath = libtorrentWrapper.getTorrentSavePath(infoHash)
                        result.success(savePath.takeIf { !it.isNullOrEmpty() })
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }
                "getAllTorrents" -> {
                    try {
                        val torrentsJson = libtorrentWrapper.getAllTorrents()  // This must return a JSON string of torrents
                        result.success(torrentsJson)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }
                "dht_putEncrypted" -> {
                    try {
                        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Expected Map arguments")
                        val key = args["key"] as? String ?: throw IllegalArgumentException("Missing key")
                        val payload = args["payload"] as? ByteArray ?: throw IllegalArgumentException("Payload is not ByteArray")

                        val success = libtorrentWrapper.dhtPutEncrypted(key, payload)
                        if (success) {
                            result.success(true)
                        } else {
                            result.error("DHT_PUT_FAIL", "Native DHT put operation failed", null)
                        }
                    } catch (e: Exception) {
                        result.error("DHT_PUT_ERROR", e.message, null)
                    }
                }



                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
