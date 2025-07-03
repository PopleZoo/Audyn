package com.example.audyn

class LibtorrentWrapper {
    companion object {
        init {
            System.loadLibrary("libtorrentwrapper")
        }
    }

    /** Returns the libtorrent wrapper version string. */
    external fun getVersion(): String

    /** Returns the info hash for the torrent file at [filePath], or null if failure. */
    external fun getInfoHash(filePath: String): String?

    /** Adds a torrent with given parameters, returns true if successful. */
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

    /** Creates a torrent from [filePath], outputs to [outputPath], with optional [trackers]. */
    external fun createTorrent(
        filePath: String,
        outputPath: String,
        trackers: Array<String>?
    ): Boolean

    /** Returns torrent statistics as JSON string. */
    external fun getTorrentStats(): String

    /** Returns swarm info JSON string for the torrent identified by [infoHash], or null. */
    external fun getSwarmInfo(infoHash: String): String?

    /** Removes the torrent with the specified [infoHash], returns true if success. */
    external fun removeTorrentByInfoHash(infoHash: String): Boolean

    /** Cleans up the libtorrent session and resources. */
    external fun cleanupSession()

    /** Returns the save path for the torrent identified by [infoHash], or null if not found. */
    external fun getTorrentSavePath(infoHash: String): String?
}
