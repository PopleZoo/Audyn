import 'dart:typed_data';
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

  /// NEW: Adds a torrent from raw torrent file bytes directly.
  static Future<bool> addTorrentFromBytes(Uint8List torrentBytes, {
    required String savePath,
    bool seedMode = false,
    bool announce = false,
    bool enableDHT = false,
    bool enableLSD = true,
    bool enableUTP = true,
    bool enableTrackers = false,
    bool enablePeerExchange = true,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('addTorrentFromBytes', {
        'torrentBytes': torrentBytes,
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
      debugPrint('[LibtorrentWrapper] addTorrentFromBytes error: $e\n$stacktrace');
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
  /// Consider removing if no longer used.
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
  /// Consider removing or replacing if infoHash no longer used.
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
  /// You may remove this if no longer using infoHash.
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

  /// Get the save path (download folder) for a torrent by its infoHash.
  /// Consider removing or adapting this method if infoHash is dropped.
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

  /// Removes a torrent by its torrent name instead of infoHash.
  /// This requires native-side support for removing torrents by name.
  static Future<bool> removeTorrentByName(String torrentName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'removeTorrentByName',
        {'torrentName': torrentName},
      );
      return result == true;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] removeTorrentByName error: $e\n$stacktrace');
      return false;
    }
  }
}
