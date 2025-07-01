package com.example.audyn

import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class LibtorrentWrapper {

    companion object {
        init {
            System.loadLibrary("libtorrentwrapper")
        }
    }

    external fun getVersion(): String
    external fun getInfoHash(filePath: String): String?
    external fun addTorrent(
        filePath: String,
        savePath: String,
        seedMode: Boolean,
        announce: Boolean,
        enableDHT: Boolean,
        enableLSD: Boolean,
        enableUTP: Boolean,
        enableTrackers: Boolean,
        enablePeerExchange: Boolean
    ): Boolean

    external fun createTorrent(
        filePath: String,
        outputPath: String,
        trackers: Array<String>?
    ): Boolean

    external fun getTorrentStats(): String
    external fun getSwarmInfo(infoHash: String): String?
    external fun removeTorrentByInfoHash(infoHash: String): Boolean
    external fun cleanupSession()
    external fun getTorrentSavePath(infoHash: String): String?

    // If you want to keep these suspend wrappers, you need to pass in a MethodChannel reference
    // For now, they will throw if used because 'channel' does not exist in this class.
    // Remove or adapt as needed.

    suspend fun getMetadataForTorrent(infoHash: String): String? =
        invokeMethodSuspend("getMetadataForTorrent", infoHash)

    suspend fun getPieceAvailability(infoHash: String): List<Boolean>? =
        invokeMethodSuspend("getPieceAvailability", infoHash)

    suspend fun streamPieceData(infoHash: String, pieceIndex: Int): ByteArray? =
        invokeMethodSuspend("streamPieceData", mapOf("infoHash" to infoHash, "pieceIndex" to pieceIndex))

    private suspend inline fun <reified T> invokeMethodSuspend(method: String, argument: Any?): T? =
        suspendCancellableCoroutine { cont ->
            // Since 'channel' no longer exists here, you need to provide it somehow or remove these functions.
            cont.resumeWithException(UnsupportedOperationException("No MethodChannel available"))
        }

    private fun debugPrint(message: String) {
        // TODO: Replace with your preferred logging
        println(message)
    }
}
