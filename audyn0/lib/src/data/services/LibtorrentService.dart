import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ************************************************************
/// 🌐 LIBTORRENT SERVICE (NO INFO_HASH, USE TORRENT NAME INSTEAD)
/// ************************************************************

class LibtorrentService {
  static const _ch = MethodChannel('libtorrent_wrapper');

  /// Get libtorrent version
  Future<String> getVersion() async =>
      (await _ch.invokeMethod<String>('getVersion')) ?? 'unknown';

  /// Cleanup session
  Future<void> cleanupSession() async =>
      await _ch.invokeMethod('cleanupSession');

  /// Add torrent by file path and save path
  Future<bool> addTorrent(String filePath, String savePath,
      {bool seedMode = true,
        bool announce = false,
        bool enableDHT = false,
        bool enableLSD = true,
        bool enableUTP = true,
        bool enableTrackers = false,
        bool enablePeerExchange = true}) async {
    try {
      final ok = await _ch.invokeMethod('addTorrent', {
        'filePath': filePath,
        'savePath': savePath,
        'seedMode': seedMode,
        'announce': announce,
        'enableDHT': enableDHT,
        'enableLSD': enableLSD,
        'enableUTP': enableUTP,
        'enableTrackers': enableTrackers,
        'enablePeerExchange': enablePeerExchange,
      });
      return ok == true;
    } catch (e) {
      debugPrint('[addTorrent] error: $e');
      return false;
    }
  }

  /// Create a torrent file and seed it; returns torrent name
  Future<String?> createTorrentAndGetName(String filePath) async {
    final tmpDir = await getTemporaryDirectory();
    final torrentPath = p.join(tmpDir.path, '${p.basenameWithoutExtension(filePath)}.torrent');

    final success = await _ch.invokeMethod('createTorrent', {
      'filePath': filePath,
      'outputPath': torrentPath,
    });

    if (success != true) return null;

    final torrentName = p.basename(filePath);

    // Add torrent (seed mode), DHT disabled for encrypted usage
    await addTorrent(torrentPath, p.dirname(filePath), seedMode: true, enableDHT: false);

    return torrentName;
  }

  /// Get all torrents as JSON-decoded list
  Future<List<Map<String, dynamic>>> getAllTorrents() async {
    try {
      final raw = await _ch.invokeMethod<String>('getAllTorrents');
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);

      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }

      if (decoded is Map<String, dynamic> && decoded.containsKey('torrents')) {
        final torrents = decoded['torrents'];
        if (torrents is List) {
          return torrents.whereType<Map<String, dynamic>>().toList();
        }
      }

      return [];
    } catch (e, st) {
      debugPrint('[getAllTorrents] error: $e\n$st');
      return [];
    }
  }

  /// Remove torrent by name
  Future<bool> removeTorrentByName(String torrentName) async {
    try {
      final result = await _ch.invokeMethod('removeTorrentByName', {'torrentName': torrentName});
      return result == true;
    } catch (e) {
      debugPrint('[removeTorrentByName] error: $e');
      return false;
    }
  }

  /// Get save path of a torrent by name
  Future<String?> getTorrentSavePathByName(String torrentName) async {
    try {
      final res = await _ch.invokeMethod<String>('getTorrentSavePathByName', {'torrentName': torrentName});
      return res;
    } catch (e) {
      debugPrint('[getTorrentSavePathByName] error: $e');
      return null;
    }
  }
}