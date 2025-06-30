import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class LibtorrentWrapper {
  static const MethodChannel _channel = MethodChannel('libtorrent_wrapper');

  /// Adds a torrent file to the session with full swarm config.
  static Future<bool> addTorrent(
      String torrentFilePath, {
        required String savePath,
        bool seedMode = false,
        bool announce = false,
        bool enableDHT = true,
        bool enableLSD = true,
        bool enableUTP = true,
        bool enableTrackers = true,
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
      });
      return result == true;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] addTorrent error: $e\n$stacktrace');
      return false;
    }
  }

  /// Gets libtorrent version.
  static Future<String> getVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('getVersion');
      return version ?? 'Unknown';
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getVersion error: $e\n$stacktrace');
      return 'Unknown';
    }
  }

  /// Creates a .torrent file from a given path.
  static Future<bool> createTorrent(
      String path,
      String torrentFilePath, {
        List<String>? trackers,
      }) async {
    try {
      final Map<String, dynamic> args = {
        'filePath': path,
        'outputPath': torrentFilePath,
      };

      if (trackers != null && trackers.isNotEmpty) {
        args['trackers'] = trackers;
      }

      final result = await _channel.invokeMethod<bool>('createTorrent', args);
      return result == true;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] createTorrent error: $e\n$stacktrace');
      return false;
    }
  }

  /// Extracts the info hash from a .torrent file.
  static Future<String?> getInfoHash(String torrentPath) async {
    try {
      final result = await _channel.invokeMethod<String>('getInfoHash', torrentPath);
      return (result != null && result.isNotEmpty) ? result : null;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getInfoHash error: $e\n$stacktrace');
      return null;
    }
  }

  /// Gets torrent stats (list of objects in JSON).
  static Future<String> getTorrentStats() async {
    try {
      final result = await _channel.invokeMethod<String>('getTorrentStats');
      return result ?? '[]';
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getTorrentStats error: $e\n$stacktrace');
      return '[]';
    }
  }

  /// Retrieves swarm info for a given info hash (optional extension).
  static Future<String?> getSwarmInfo(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<String>('getSwarmInfo', infoHash);
      return result;
    } catch (e, stacktrace) {
      debugPrint('[LibtorrentWrapper] getSwarmInfo error: $e\n$stacktrace');
      return null;
    }
  }

  /// Removes a torrent by info hash from the libtorrent session.
  static Future<bool> removeTorrentByInfoHash(String infoHash) async {
    try {
      final bool result = await _channel.invokeMethod<bool>(
        'removeTorrentByInfoHash',
        {'infoHash': infoHash},
      ) ?? false;
      return result;
    } catch (e) {
      debugPrint('[LibtorrentWrapper] Failed to remove torrent: $e');
      return false;
    }
  }

}
