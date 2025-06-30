package com.example.audyn

class LibtorrentWrapper {
    companion object {
        init {
            System.loadLibrary("libtorrentwrapper")
        }
    }

    /** Returns libtorrent version string */
    external fun getVersion(): String

    /** Extracts the info hash from a .torrent file */
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


    /**
     * Creates a .torrent file from a file/folder
     * @param filePath Path to the source file/folder
     * @param outputPath Output .torrent file location
     * @param trackers Optional tracker list
     */
    external fun createTorrent(
        filePath: String,
        outputPath: String,
        trackers: Array<String>?
    ): Boolean

    /** Returns the current torrent stats in JSON format */
    external fun getTorrentStats(): String

    /**
     * Returns swarm info for a given infoHash
     * @param infoHash Hex string (40 characters)
     */
    external fun getSwarmInfo(infoHash: String): String?

    /**
     * Removes torrent by its info hash
     * @param infoHash Hex string
     */
    external fun removeTorrentByInfoHash(infoHash: String): Boolean

    /** Cleans up the session and removes all torrents */
    external fun cleanupSession()
}
