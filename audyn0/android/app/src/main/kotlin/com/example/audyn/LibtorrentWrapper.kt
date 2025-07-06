package com.example.audyn

import android.content.Context
import java.io.File

class LibtorrentWrapper(private val context: Context) {

    companion object {
        init {
            System.loadLibrary("libtorrentwrapper")
        }
    }

    /* ---------- ORIGINAL API (unchanged) ---------- */
    external fun getVersion(): String
    external fun addTorrent(
        filePath: String, savePath: String,
        seedMode: Boolean, announce: Boolean,
        enableDHT: Boolean, enableLSD: Boolean, enableUTP: Boolean,
        enableTrackers: Boolean, enablePeerExchange: Boolean
    ): Boolean
    external fun getAllTorrents(): String
    external fun createTorrent(
        filePath: String, outputPath: String, trackers: Array<String>? = null
    ): Boolean
    external fun removeTorrentByName(torrentName: String): Boolean
    external fun getTorrentSavePathByName(torrentName: String): String?
    external fun getTorrentStats(): String
    external fun cleanupSession()

    /* ---------- NEW “bytes” API (just added) ---------- */

    /** Build (in‑memory) *.torrent* bytes for a single file. */
    external fun createTorrentBytes(sourcePath: String): ByteArray

    /** Add a torrent from raw *.torrent* bytes already in memory. */
    external fun addTorrentFromBytes(
        torrentBytes: ByteArray,      // raw *.torrent*
        savePath:   String,
        seedMode:   Boolean, announce: Boolean,
        enableDHT:  Boolean, enableLSD: Boolean, enableUTP: Boolean,
        enableTrackers: Boolean, enablePeerExchange: Boolean
    ): Boolean


    /* ---------- tiny helper you already had ---------- */
    fun createTorrentInAppDir(sourceFilePath: String,
                              trackers: Array<String>? = null): Boolean {
        val torrentName = File(sourceFilePath).nameWithoutExtension + ".torrent"
        val output      = File(context.filesDir, torrentName)
        return createTorrent(sourceFilePath, output.absolutePath, trackers)
    }

}
