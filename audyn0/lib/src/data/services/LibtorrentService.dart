import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/CryptoHelper.dart';

/// ************************************************************
/// 🌐 2. LIBTORRENT SERVICE (WITH ENCRYPTED DHT SUPPORT REMOVED INFOHASH USAGE)
/// ************************************************************
class LibtorrentService {
  static const _ch = MethodChannel('libtorrent_wrapper');
  static const _prefix = 'audynapp:'; // DHT key prefix (still kept but no infoHash)
  static const Duration _broadcastInterval = Duration(minutes: 1);

  Timer? _broadcastTimer;

  LibtorrentService() {
    _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => broadcastLocalSwarmData());
  }

  /// Basic interop calls
  Future<String> getVersion() async =>
      (await _ch.invokeMethod<String>('getVersion')) ?? 'unknown';

  Future<void> cleanupSession() async =>
      _ch.invokeMethod('cleanupSession');

  /// Removed infoHash param: delete torrent by name instead
  Future<bool> removeTorrentByName(String torrentName) async {
    try {
      final success = await _ch.invokeMethod('removeTorrentByName', {'name': torrentName});
      return success == true;
    } catch (e) {
      debugPrint('[removeTorrentByName] error: $e');
      return false;
    }
  }

  Future<String> getTorrentStats() async =>
      (await _ch.invokeMethod<String>('getTorrentStats')) ?? '[]';

  /// Removed infoHash param
  Future<String?> getTorrentSavePathByName(String torrentName) async =>
      await _ch.invokeMethod<String>('getTorrentSavePathByName', {'name': torrentName});

  /// Create a torrent and seed it, returning its name instead of infoHash
  Future<String?> createTorrentAndGetName(String filePath) async {
    final tmp = await getTemporaryDirectory();
    final torrentPath = p.join(tmp.path, '${p.basenameWithoutExtension(filePath)}.torrent');

    final ok = await _ch.invokeMethod('createTorrent', {
      'filePath': filePath,
      'outputPath': torrentPath,
    });

    if (ok != true) return null;

    final torrentName = p.basename(filePath);

    await addTorrent(torrentPath, p.dirname(filePath), seedMode: true, enableDHT: false);

    // NOTE: Removed DHT encryption broadcast since no infoHash, or
    // you may implement your own unique key system based on name if needed

    return torrentName;
  }

  Future<bool> addTorrent(String filePath, String savePath,
      {bool seedMode = true,
        bool announce = false,
        bool enableDHT = false, // Disabled due to no infoHash
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

  /// Removed encrypted swarm data methods since no infoHash key available.
  /// You may want to implement a different system based on torrentName.

  /// Broadcast all local torrents periodically into DHT (disabled DHT usage)
  Future<void> broadcastLocalSwarmData() async {
    try {
      final raw = await _ch.invokeMethod<String>('getAllTorrents');
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);

      List<Map<String, dynamic>> torrents = [];

      if (decoded is Map<String, dynamic> && decoded.containsKey('torrents')) {
        final torrentList = decoded['torrents'];
        if (torrentList is List) {
          torrents = torrentList.whereType<Map<String, dynamic>>().toList();
        } else if (torrentList is Map<String, dynamic>) {
          torrents = [torrentList];
        } else {
          debugPrint('[broadcastLocalSwarmData] Unexpected torrents format: ${torrentList.runtimeType}');
          return;
        }
      } else if (decoded is List) {
        torrents = decoded.whereType<Map<String, dynamic>>().toList();
      } else {
        debugPrint('[broadcastLocalSwarmData] Unexpected JSON type: ${decoded.runtimeType}');
        return;
      }

      for (final t in torrents) {
        final torrentName = (t['name'] ?? '').toString();
        if (torrentName.isEmpty) continue;

        // No DHT broadcast due to missing infoHash encryption
        // If you want, implement broadcast by name key here
      }
    } catch (e, st) {
      debugPrint('[broadcastLocalSwarmData] error: $e\n$st');
    }
  }

  void dispose() {
    _broadcastTimer?.cancel();
  }

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
}
