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
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }
                    val filePath = args["filePath"] as? String
                    val savePath = args["savePath"] as? String
                    if (filePath.isNullOrEmpty() || savePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "Missing or empty filePath or savePath", null)
                        return@setMethodCallHandler
                    }

                    val seedMode = args["seedMode"] as? Boolean ?: false
                    val announce = args["announce"] as? Boolean ?: false
                    val enableDHT = args["enableDHT"] as? Boolean ?: true
                    val enableLSD = args["enableLSD"] as? Boolean ?: true
                    val enableUTP = args["enableUTP"] as? Boolean ?: true
                    val enableTrackers = args["enableTrackers"] as? Boolean ?: true
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
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }

                    val filePath = args["filePath"] as? String
                    val outputPath = args["outputPath"] as? String
                    val trackersList = args["trackers"] as? List<String>
                    val trackersArray = trackersList?.toTypedArray()

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
                    val filePath = call.arguments as? String
                    if (filePath.isNullOrEmpty()) {
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
                    val infoHash = call.arguments as? String
                    if (infoHash.isNullOrEmpty()) {
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
                    val infoHash = call.argument<String>("infoHash")
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
                    val infoHash = call.argument<String>("infoHash")
                    if (infoHash.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "infoHash is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savePath = libtorrentWrapper.getTorrentSavePath(infoHash)
                        if (savePath.isNullOrEmpty()) {
                            result.success(null) // or result.error(...) if you want
                        } else {
                            result.success(savePath)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
