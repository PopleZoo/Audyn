import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class LibtorrentWrapper {
  static const MethodChannel _channel = MethodChannel('libtorrent_wrapper');

  static Future<bool> addTorrent(
      String torrentFilePath, {
        required String savePath,
        bool seedMode = false,
        bool announce = false,
        bool enableDHT = false,        // 🔕 Disable public DHT
        bool enableLSD = true,         // ✅ Enable local peer discovery
        bool enableUTP = true,
        bool enableTrackers = false,   // 🔕 Disable public trackers
        bool enablePeerExchange = true // ✅ Local peer gossip
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

  static Future<String> getVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getVersion');
      return version ?? 'Unknown';
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getVersion error: $e\n$stacktrace');
      return 'Unknown';
    }
  }

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

  static Future<String?> getInfoHash(String torrentPath) async {
    try {
      final result = await _channel.invokeMethod<String>('getInfoHash', torrentPath);
      if (result != null && result.isNotEmpty) return result;
      return null;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getInfoHash error: $e\n$stacktrace');
      return null;
    }
  }

  static Future<String> getTorrentStats() async {
    try {
      final result = await _channel.invokeMethod<String>('getTorrentStats');
      return result ?? '[]';
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getTorrentStats error: $e\n$stacktrace');
      return '[]';
    }
  }

  static Future<String?> getSwarmInfo(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<String>('getSwarmInfo', infoHash);
      return result;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getSwarmInfo error: $e\n$stacktrace');
      return null;
    }
  }

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
