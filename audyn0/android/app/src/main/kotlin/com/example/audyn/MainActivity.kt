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
            try {
                when (call.method) {
                    "getVersion" -> {
                        val version = libtorrentWrapper.getVersion()
                        result.success(version)
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

                        val success = libtorrentWrapper.addTorrent(
                            filePath, savePath, seedMode, announce,
                            enableDHT, enableLSD, enableUTP,
                            enableTrackers, enablePeerExchange
                        )
                        result.success(success)
                    }

                    "createTorrent" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
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

                        val success = libtorrentWrapper.createTorrent(filePath, outputPath, trackersArray)
                        result.success(success)
                    }

                    "getTorrentStats" -> {
                        val statsJson = libtorrentWrapper.getTorrentStats()
                        result.success(statsJson)
                    }

                    "getInfoHash" -> {
                        val filePath = call.arguments as? String
                        if (filePath.isNullOrEmpty()) {
                            result.error("ARG_ERROR", "Expected non-empty filePath string", null)
                            return@setMethodCallHandler
                        }
                        val hash = libtorrentWrapper.getInfoHash(filePath)
                        if (hash.isNullOrEmpty()) {
                            result.error("HASH_ERROR", "Failed to extract info hash", null)
                        } else {
                            result.success(hash)
                        }
                    }

                    "getSwarmInfo" -> {
                        val infoHash = call.arguments as? String
                        if (infoHash.isNullOrEmpty()) {
                            result.error("ARG_ERROR", "Expected non-empty infoHash string", null)
                            return@setMethodCallHandler
                        }
                        val swarmInfo = libtorrentWrapper.getSwarmInfo(infoHash)
                        result.success(swarmInfo)
                    }

                    "removeTorrentByInfoHash" -> {
                        val infoHash = call.argument<String>("infoHash")
                        if (infoHash.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "infoHash is required", null)
                            return@setMethodCallHandler
                        }
                        val success = libtorrentWrapper.removeTorrentByInfoHash(infoHash)
                        result.success(success)
                    }

                    "cleanupSession" -> {
                        libtorrentWrapper.cleanupSession()
                        result.success(null)
                    }

                    "getTorrentSavePath" -> {
                        val infoHash = call.argument<String>("infoHash")
                        if (infoHash.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "infoHash is required", null)
                            return@setMethodCallHandler
                        }
                        val savePath = libtorrentWrapper.getTorrentSavePath(infoHash)
                        result.success(savePath) // null is allowed here
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error("ERROR", e.localizedMessage ?: "Unknown error", null)
            }
        }
    }
}
