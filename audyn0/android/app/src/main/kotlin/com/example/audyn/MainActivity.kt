package com.example.audyn

import android.content.Context
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    private val CHANNEL = "libtorrent_wrapper"
    // Pass context to LibtorrentWrapper for internal path handling
    private lateinit var libtorrentWrapper: LibtorrentWrapper

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        libtorrentWrapper = LibtorrentWrapper(this)  // pass context here
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                "removeTorrentByName" -> {
                    val args = call.arguments
                    val torrentName = when (args) {
                        is String -> args
                        is Map<*, *> -> args["torrentName"] as? String
                        else -> null
                    }
                    if (torrentName.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "torrentName is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val success = libtorrentWrapper.removeTorrentByName(torrentName)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "getTorrentSavePathByName" -> {
                    val args = call.arguments
                    val torrentName: String? = when (args) {
                        is String -> args
                        is Map<*, *> -> args["torrentName"] as? String
                        else -> null
                    }
                    if (torrentName.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "torrentName is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savePath = libtorrentWrapper.getTorrentSavePathByName(torrentName)
                        result.success(savePath)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "addTorrent" -> {
                    val args = call.arguments

                    if (args !is Map<*, *>) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }

                    val filePath = args["filePath"] as? String
                    val savePath = args["savePath"] as? String

                    if (filePath.isNullOrEmpty() || savePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "filePath or savePath missing", null)
                        return@setMethodCallHandler
                    }

                    val seedMode = args["seedMode"] as? Boolean ?: false
                    val announce = args["announce"] as? Boolean ?: false
                    val enableDHT = args["enableDHT"] as? Boolean ?: true
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

                "getTorrentStats" -> {
                    try {
                        val statsJson = libtorrentWrapper.getTorrentStats()
                        result.success(statsJson)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                "getAllTorrents" -> {
                    try {
                        val torrentsJson = libtorrentWrapper.getAllTorrents()
                        result.success(torrentsJson)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                // New handler to create torrent inside app dir automatically
                "createTorrentInAppDir" -> {
                    val args = call.arguments
                    if (args !is Map<*, *>) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }

                    val filePath = args["filePath"] as? String
                    val trackersList = args["trackers"] as? List<*>

                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    val trackersArray = trackersList
                        ?.filterIsInstance<String>()
                        ?.toTypedArray()

                    try {
                        val success = libtorrentWrapper.createTorrentInAppDir(filePath, trackersArray)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("ERROR", e.localizedMessage, null)
                    }
                }

                // Keep old createTorrent method (optional)
                "createTorrent" -> {
                    val args = call.arguments
                    if (args !is Map<*, *>) {
                        result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                        return@setMethodCallHandler
                    }

                    val filePath = args["filePath"] as? String
                    val outputPath = args["outputPath"] as? String
                    val trackersList = args["trackers"] as? List<*>

                    if (filePath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "filePath or outputPath is required", null)
                        return@setMethodCallHandler
                    }

                    val trackersArray = trackersList
                        ?.filterIsInstance<String>()
                        ?.toTypedArray()

                    try {
                        val success = libtorrentWrapper.createTorrent(filePath, outputPath, trackersArray)
                        result.success(success)
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
