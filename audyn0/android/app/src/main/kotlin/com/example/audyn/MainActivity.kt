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
                    val version = libtorrentWrapper.getVersion()
                    result.success(version)
                }

                "addTorrent" -> {
                    val filePath = call.argument<String>("filePath")
                    val savePath = call.argument<String>("savePath")
                    val seedMode = call.argument<Boolean>("seedMode") ?: false
                    val announce = call.argument<Boolean>("announce") ?: false
                    val enableDHT = call.argument<Boolean>("enableDHT") ?: true
                    val enableLSD = call.argument<Boolean>("enableLSD") ?: true
                    val enableUTP = call.argument<Boolean>("enableUTP") ?: true
                    val enableTrackers = call.argument<Boolean>("enableTrackers") ?: true
                    // val trackersList = call.argument<List<String>>("trackers") // Not used since addTorrent doesn't accept it

                    if (filePath != null && savePath != null) {
                        val success = libtorrentWrapper.addTorrent(
                            filePath,
                            savePath,
                            seedMode,
                            announce,
                            enableDHT,
                            enableLSD,
                            enableUTP,
                            enableTrackers
                            // trackersArray removed here!
                        )
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Missing filePath or savePath argument", null)
                    }
                }


                "createTorrent" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        val filePath = args["filePath"] as? String
                        val outputPath = args["outputPath"] as? String
                        val trackersList = args["trackers"] as? List<String>
                        val trackersArray = trackersList?.toTypedArray()

                        if (filePath != null && outputPath != null) {
                            val success = libtorrentWrapper.createTorrent(filePath, outputPath, trackersArray)
                            result.success(success)
                        } else {
                            result.error("INVALID_ARGUMENT", "Missing filePath or outputPath argument", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Expected Map arguments", null)
                    }
                }

                "getTorrentStats" -> {
                    val statsJson = libtorrentWrapper.getTorrentStats()
                    result.success(statsJson)
                }

                "getInfoHash" -> {
                    val filePath = call.arguments as? String
                    if (filePath != null) {
                        val hash = libtorrentWrapper.getInfoHash(filePath)
                        if (hash != null) {
                            result.success(hash)
                        } else {
                            result.error("HASH_ERROR", "Failed to extract info hash", null)
                        }
                    } else {
                        result.error("ARG_ERROR", "Expected filePath", null)
                    }
                }

                "getSwarmInfo" -> {
                    val infoHash = call.arguments as? String
                    if (infoHash != null) {
                        val swarmInfoJson = libtorrentWrapper.getSwarmInfo(infoHash)
                        result.success(swarmInfoJson)
                    } else {
                        result.error("ARG_ERROR", "Expected infoHash string", null)
                    }
                }

                "removeTorrentByInfoHash" -> {
                    val infoHash = call.argument<String>("infoHash")
                    if (infoHash != null) {
                        val success = libtorrentWrapper.removeTorrentByInfoHash(infoHash) // ✅ FIXED LINE
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "infoHash is required", null)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
