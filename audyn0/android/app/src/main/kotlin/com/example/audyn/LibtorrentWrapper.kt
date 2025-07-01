package com.example.audyn

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
}
