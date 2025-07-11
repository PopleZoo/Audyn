package com.example.audyn

import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {

    /** ⚠ Don’t change – Dart side uses the same name */
    private val CHANNEL = "libtorrentwrapper"

    /** JNI wrapper instance with Android context */
    private lateinit var libtorrentWrapper: LibtorrentWrapper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        libtorrentWrapper = LibtorrentWrapper(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    /*───────────────────────────────*
                     *  TORRENT‑REMOVAL HELPERS
                     *───────────────────────────────*/
                    "removeTorrentByName" -> {
                        val torrentName = when (val a = call.arguments) {
                            is String      -> a
                            is Map<*, *>   -> a["torrentName"] as? String
                            else           -> null
                        }

                        if (torrentName.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "torrentName is required", null)
                            return@setMethodCallHandler
                        }

                        runCatching {
                            libtorrentWrapper.removeTorrentByName(torrentName)
                        }.onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    "getTorrentSavePathByName" -> {
                        val torrentName = when (val a = call.arguments) {
                            is String      -> a
                            is Map<*, *>   -> a["torrentName"] as? String
                            else           -> null
                        }

                        if (torrentName.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "torrentName is required", null)
                            return@setMethodCallHandler
                        }

                        runCatching {
                            libtorrentWrapper.getTorrentSavePathByName(torrentName)
                        }.onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    /*───────────────────────────────*
                     *  ADD TORRENT (FILE‑BASED)
                     *───────────────────────────────*/
                    "addTorrent" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                            return@setMethodCallHandler
                        }

                        val filePath         = args["filePath"]  as? String ?: run {
                            result.error("INVALID_ARGUMENT", "filePath missing", null); return@setMethodCallHandler
                        }
                        val savePath         = args["savePath"]  as? String ?: run {
                            result.error("INVALID_ARGUMENT", "savePath missing", null); return@setMethodCallHandler
                        }

                        val seedMode         = args["seedMode"]         as? Boolean ?: false
                        val announce         = args["announce"]         as? Boolean ?: false
                        val enableDHT        = args["enableDHT"]        as? Boolean ?: true
                        val enableLSD        = args["enableLSD"]        as? Boolean ?: true
                        val enableUTP        = args["enableUTP"]        as? Boolean ?: true
                        val enableTrackers   = args["enableTrackers"]   as? Boolean ?: false
                        val enablePeerEx     = args["enablePeerExchange"] as? Boolean ?: true

                        runCatching {
                            libtorrentWrapper.addTorrent(
                                filePath, savePath,
                                seedMode, announce,
                                enableDHT, enableLSD, enableUTP,
                                enableTrackers, enablePeerEx
                            )
                        }.onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    /*───────────────────────────────*
                     *  CREATE TORRENT (FILE → BYTES)
                     *───────────────────────────────*/
                    "createTorrentBytes" -> {
                        val args       = call.arguments as? Map<*, *>
                        val sourcePath = args?.get("sourcePath") as? String

                        if (sourcePath.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "sourcePath is required", null)
                            return@setMethodCallHandler
                        }

                        runCatching { libtorrentWrapper.createTorrentBytes(sourcePath) }
                            .onSuccess(result::success)
                            .onFailure { e -> result.error("NATIVE_ERROR", e.localizedMessage, null) }
                    }
                    "startTorrentByHash" -> {
                        val args = call.arguments as? Map<*, *>
                        val infoHash = args?.get("infoHash") as? String

                        if (infoHash.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "Expected a string infoHash", null)
                            return@setMethodCallHandler
                        }

                        val success = libtorrentWrapper.startTorrentByHash(infoHash)
                        result.success(success)
                    }


                    "stopTorrentByHash" -> {
                        val args = call.arguments as? Map<*, *>
                        val infoHash = args?.get("infoHash") as? String

                        if (infoHash.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "infoHash is required", null)
                            return@setMethodCallHandler
                        }

                        runCatching {
                            libtorrentWrapper.stopTorrentByHash(infoHash)
                        }.onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }


                    /*───────────────────────────────*
                     *  ADD TORRENT (BYTES)
                     *───────────────────────────────*/
                    "addTorrentFromBytes" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("INVALID_ARGUMENT", "Map expected", null)
                            return@setMethodCallHandler
                        }

                        val torrentBytes   = args["torrentBytes"] as? ByteArray
                        val savePath       = args["savePath"]     as? String
                        if (torrentBytes == null || savePath == null) {
                            result.error("INVALID_ARGUMENT", "torrentBytes or savePath missing", null)
                            return@setMethodCallHandler
                        }

                        val seedMode       = args["seedMode"]        as? Boolean ?: false
                        val announce       = args["announce"]        as? Boolean ?: false
                        val enableDHT      = args["enableDHT"]       as? Boolean ?: true
                        val enableLSD      = args["enableLSD"]       as? Boolean ?: true
                        val enableUTP      = args["enableUTP"]       as? Boolean ?: true
                        val enableTrackers = args["enableTrackers"]  as? Boolean ?: false
                        val enablePEX      = args["enablePeerExchange"] as? Boolean ?: true

                        runCatching {
                            libtorrentWrapper.addTorrentFromBytes(
                                torrentBytes, savePath,
                                seedMode, announce,
                                enableDHT, enableLSD, enableUTP,
                                enableTrackers, enablePEX
                            )
                        }.onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    /*───────────────────────────────*
                     *  INFORMATION QUERIES
                     *───────────────────────────────*/
                    "getTorrentStats" -> {
                        runCatching { libtorrentWrapper.getTorrentStats() }
                            .onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    "getAllTorrents" -> {
                        runCatching { libtorrentWrapper.getAllTorrents() }
                            .onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    /*───────────────────────────────*
                     *  (OPTIONAL) CREATE TORRENT FILE
                     *───────────────────────────────*/
                    "createTorrent" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                            return@setMethodCallHandler
                        }

                        val filePath   = args["filePath"]   as? String
                        val outputPath = args["outputPath"] as? String
                        if (filePath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "filePath or outputPath missing", null)
                            return@setMethodCallHandler
                        }

                        val trackers   = (args["trackers"] as? List<*>)?.filterIsInstance<String>()?.toTypedArray()

                        runCatching { libtorrentWrapper.createTorrent(filePath, outputPath, trackers) }
                            .onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    "createTorrentInAppDir" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args == null) {
                            result.error("INVALID_ARGUMENT", "Expected map arguments", null)
                            return@setMethodCallHandler
                        }

                        val filePath = args["filePath"] as? String
                        if (filePath.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "filePath is required", null)
                            return@setMethodCallHandler
                        }

                        val trackers = (args["trackers"] as? List<*>)?.filterIsInstance<String>()?.toTypedArray()

                        runCatching { libtorrentWrapper.createTorrentInAppDir(filePath, trackers) }
                            .onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    "isTorrentActive" -> {
                        val infoHash = when (val arg = call.arguments) {
                            is String -> arg
                            is Map<*, *> -> arg["infoHash"] as? String
                            else -> null
                        }

                        if (infoHash.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "infoHash is required", null)
                            return@setMethodCallHandler
                        }

                        runCatching {
                            libtorrentWrapper.isTorrentActive(infoHash)
                        }.onSuccess(result::success)
                            .onFailure { e -> result.error("ERROR", e.localizedMessage, null) }
                    }

                    "getInfoHash" -> {
                        val torrentPath = call.arguments as? String
                        if (torrentPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGUMENT", "torrentPath is required", null)
                            return@setMethodCallHandler
                        }

                        runCatching {
                            libtorrentWrapper.getInfoHash(torrentPath) // make sure this method exists in your wrapper
                        }.onSuccess { infoHash ->
                            result.success(infoHash)
                        }.onFailure { e ->
                            result.error("ERROR", e.localizedMessage, null)
                        }
                    }
                    "getInfoHashFromDecryptedBytes" -> {
                        val args = call.arguments as? Map<*, *>
                        val torrentBytes = args?.get("torrentBytes") as? ByteArray

                        if (torrentBytes == null) {
                            result.error("INVALID_ARGUMENT", "torrentBytes is required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val infoHash = libtorrentWrapper.getInfoHashFromBytes(torrentBytes)
                            result.success(infoHash)
                        } catch (e: Exception) {
                            result.error("NATIVE_ERROR", e.localizedMessage, null)
                        }
                    }


                    /*───────────────────────────────*
                     *  FALLBACK
                     *───────────────────────────────*/
                    else -> result.notImplemented()
                }
            }
    }
}
