package com.example.audyn

class LibtorrentWrapper {
    companion object {
        init {
            System.loadLibrary("libtorrentwrapper")
        }
    }

    /**
     * Returns the libtorrent version string.
     * @return version string, e.g. "1.2.15.0"
     */
    external fun getVersion(): String

    /**
     * Extracts the info hash from a .torrent file.
     * @param filePath Absolute path to the .torrent file
     * @return 40-character hex string or null on error
     */
    external fun getInfoHash(filePath: String): String?

    /**
     * Adds a torrent to the session.
     * Used for seeding or downloading.
     *
     * @param filePath Path to the .torrent file
     * @param savePath Where to save/download the files
     * @param seedMode If true, assume files are already complete
     * @param announce If true, announces to trackers immediately
     * @param enableDHT Enable/disable public DHT
     * @param enableLSD Enable/disable local peer discovery
     * @param enableUTP Enable/disable uTP protocol
     * @param enableTrackers Enable/disable trackers in .torrent file
     * @param enablePeerExchange Enable/disable peer exchange
     * @return true on success, false otherwise
     */
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
     * Creates a .torrent file from a file or folder.
     *
     * @param filePath Absolute path to file or folder
     * @param outputPath Output .torrent file location
     * @param trackers Optional list of trackers
     * @return true on success, false on failure
     */
    external fun createTorrent(
        filePath: String,
        outputPath: String,
        trackers: Array<String>?
    ): Boolean

    /**
     * Returns a JSON string of all active torrents.
     * Each torrent includes name, progress, infoHash, peers, etc.
     *
     * @return JSON array as string (e.g. [ {...}, {...} ])
     */
    external fun getTorrentStats(): String

    /**
     * Returns swarm information (peers, seeds, etc.) for a specific torrent.
     *
     * @param infoHash 40-character hex string
     * @return JSON object string or null on error
     */
    external fun getSwarmInfo(infoHash: String): String?

    /**
     * Removes a torrent by its info hash.
     * Stops seeding/downloading and removes metadata.
     *
     * @param infoHash 40-character hex string
     * @return true if successful, false otherwise
     */
    external fun removeTorrentByInfoHash(infoHash: String): Boolean

    /**
     * Cleans up the entire session.
     * Useful for app shutdown or resetting the torrent engine.
     */
    external fun cleanupSession()
}
