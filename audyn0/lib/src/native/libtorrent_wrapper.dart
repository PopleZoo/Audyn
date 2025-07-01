import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class LibtorrentWrapper {
  static const MethodChannel _channel = MethodChannel('libtorrent_wrapper');

  /// Adds a torrent to the libtorrent session.
  /// Use this to join or seed Audyn P2P-only torrents.
  static Future<bool> addTorrent(
      String torrentFilePath, {
        required String savePath,
        bool seedMode = false,
        bool announce = false,
        bool enableDHT = false,         // 🔕 Disable public DHT
        bool enableLSD = true,          // ✅ Enable local peer discovery
        bool enableUTP = true,
        bool enableTrackers = false,    // 🔕 Disable public trackers
        bool enablePeerExchange = true, // ✅ Local peer gossip
      }) async {
    try {
      final result = await _channel.invokeMethod<bool>('addTorrent', {
        'filePath': torrentFilePath,
        'savePath': savePath,
        'seedMode': seedMode,
        'announce': announce,
        'enableDHT': enableDHT,
        'enableLSD': enableLSD,
        'enableUTP': enableUTP,
        'enableTrackers': enableTrackers,
        'enablePeerExchange': enablePeerExchange,
      });
      return result == true;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] addTorrent error: $e\n$stacktrace');
      return false;
    }
  }

  /// Returns libtorrent version string.
  static Future<String> getVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getVersion');
      return version ?? 'Unknown';
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getVersion error: $e\n$stacktrace');
      return 'Unknown';
    }
  }

  /// Creates a .torrent file from a given file path.
  /// For Audyn, this should be run without trackers to enforce hash determinism.
  static Future<bool> createTorrent(
      String path,
      String torrentFilePath, {
        List<String>? trackers,
      }) async {
    try {
      final args = {
        'filePath': path,
        'outputPath': torrentFilePath,
        'trackers': trackers ?? [],
      };

      final result = await _channel.invokeMethod<bool>('createTorrent', args);
      return result == true;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] createTorrent error: $e\n$stacktrace');
      return false;
    }
  }

  /// Extracts the infoHash from a .torrent file.
  static Future<String?> getInfoHash(String torrentPath) async {
    try {
      final result = await _channel.invokeMethod<String>('getInfoHash', torrentPath);
      return (result != null && result.isNotEmpty) ? result : null;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getInfoHash error: $e\n$stacktrace');
      return null;
    }
  }

  /// Returns all active torrent stats in JSON.
  static Future<String> getTorrentStats() async {
    try {
      final result = await _channel.invokeMethod<String>('getTorrentStats');
      return result ?? '[]';
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getTorrentStats error: $e\n$stacktrace');
      return '[]';
    }
  }

  /// Retrieves swarm info for a given infoHash (if supported).
  static Future<String?> getSwarmInfo(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<String>('getSwarmInfo', infoHash);
      return result;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getSwarmInfo error: $e\n$stacktrace');
      return null;
    }
  }

  /// Removes a torrent from the session by its infoHash.
  static Future<bool> removeTorrentByInfoHash(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'removeTorrentByInfoHash',
        {'infoHash': infoHash},
      );
      return result == true;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] removeTorrentByInfoHash error: $e\n$stacktrace');
      return false;
    }
  }

  /// NEW: Get the save path (download folder) for a torrent by its infoHash.
  /// Returns null if not found or error.
  static Future<String?> getTorrentSavePath(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getTorrentSavePath',
        {'infoHash': infoHash},
      );
      return result;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getTorrentSavePath error: $e\n$stacktrace');
      return null;
    }
  }
}
