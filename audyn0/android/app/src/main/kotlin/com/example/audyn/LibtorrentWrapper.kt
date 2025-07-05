package com.example.audyn

import android.content.Context
import java.io.File

class LibtorrentWrapper(private val context: Context) {
    companion object {
        init {
            System.loadLibrary("libtorrentwrapper")
        }
    }

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

    // Helper to create torrent file in app’s internal storage directory
    fun createTorrentInAppDir(
        sourceFilePath: String,
        trackers: Array<String>? = null
    ): Boolean {
        // Get app’s internal files directory
        val appDir = context.filesDir

        // Derive torrent file name from source file, e.g. "myfile.mp3" -> "myfile.torrent"
        val sourceFile = File(sourceFilePath)
        val torrentFileName = sourceFile.nameWithoutExtension + ".torrent"

        // Construct full output path inside app directory
        val outputFile = File(appDir, torrentFileName)

        return createTorrent(sourceFilePath, outputFile.absolutePath, trackers)
    }
}
