package com.example.audyn

import android.content.Context
import java.io.File

class LibtorrentWrapper(private val context: Context) {

    companion object {
        init {
            System.loadLibrary("libtorrentwrapper") // JNI .so library
        }
    }

    /* ────────────── ORIGINAL JNI API ────────────── */

    external fun getVersion(): String

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

    external fun getAllTorrents(): String

    external fun createTorrent(
        filePath: String,
        outputPath: String,
        trackers: Array<String>? = null
    ): Boolean

    external fun removeTorrentByName(torrentName: String): Boolean

    external fun getTorrentSavePathByName(torrentName: String): String?

    external fun getTorrentStats(): String

    external fun cleanupSession()


    /* ────────────── NEW “.torrent as bytes” API ────────────── */

    /**
     * Creates a `.torrent` byte array from a source file path.
     * Typically sent back to Flutter or stored to disk manually.
     */
    external fun createTorrentBytes(sourcePath: String): ByteArray

    /**
     * Loads a torrent from raw `.torrent` bytes.
     * Assumes torrent metadata is already generated externally.
     */
    external fun addTorrentFromBytes(
        torrentBytes: ByteArray,
        savePath: String,
        seedMode: Boolean,
        announce: Boolean,
        enableDHT: Boolean,
        enableLSD: Boolean,
        enableUTP: Boolean,
        enableTrackers: Boolean,
        enablePeerExchange: Boolean
    ): Boolean


    /* ────────────── Kotlin-only helper ────────────── */

    /**
     * Generates a `.torrent` file in your app's private files dir.
     * This file is persistent and can be reused or shared.
     */
    fun createTorrentInAppDir(
        sourceFilePath: String,
        trackers: Array<String>? = null
    ): Boolean {
        val torrentName = File(sourceFilePath).nameWithoutExtension + ".torrent"
        val output = File(context.filesDir, torrentName)
        return createTorrent(sourceFilePath, output.absolutePath, trackers)
    }
}
