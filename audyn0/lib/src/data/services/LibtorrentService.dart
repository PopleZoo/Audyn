import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/CryptoHelper.dart';

/// ************************************************************
/// 🌐 2. LIBTORRENT SERVICE (WITH ENCRYPTED DHT SUPPORT)
/// ************************************************************
class LibtorrentService {
  static const _ch = MethodChannel('libtorrent_wrapper');
  static const _prefix = 'audynapp:'; // DHT key prefix
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

  Future<bool> removeTorrent(String infoHash) async =>
      (await _ch.invokeMethod('removeTorrentByInfoHash', {'infoHash': infoHash})) == true;

  Future<String> getTorrentStats() async =>
      (await _ch.invokeMethod<String>('getTorrentStats')) ?? '[]';

  Future<String?> getTorrentSavePath(String infoHash) async =>
      await _ch.invokeMethod<String>('getTorrentSavePath', infoHash);

  /// Create a torrent and seed it, returning its infoHash
  Future<String?> createTorrentAndGetHash(String filePath) async {
    final tmp = await getTemporaryDirectory();
    final torrentPath = p.join(tmp.path, '${p.basenameWithoutExtension(filePath)}.torrent');

    final ok = await _ch.invokeMethod('createTorrent', {
      'filePath': filePath,
      'outputPath': torrentPath,
    });

    if (ok != true) return null;

    final infoHash = await _ch.invokeMethod<String>('getInfoHashFromFile', torrentPath);
    if (infoHash == null) return null;

    await addTorrent(torrentPath, p.dirname(filePath), seedMode: true, enableDHT: true);

    // Publish presence in DHT
    await putEncryptedSwarmData(infoHash, {
      'infoHash': infoHash,
      'name': p.basename(filePath),
      'ts': DateTime.now().toIso8601String(),
    });

    return infoHash;
  }

  Future<bool> addTorrent(String filePath, String savePath,
      {bool seedMode = true,
        bool announce = false,
        bool enableDHT = true,
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

  /// Publish encrypted swarm data to DHT
  Future<void> putEncryptedSwarmData(String infoHash, Map<String, dynamic> data) async {
    final key = '$_prefix$infoHash';
    final encryptedPayload = CryptoHelper.encryptJson(data);
    try {
      await _ch.invokeMethod('dht_putEncrypted', {
        'key': key,
        'payload': encryptedPayload,
      });
    } catch (e, st) {
      debugPrint('[putEncryptedSwarmData] error: $e\n$st');
    }
  }

  /// Retrieve encrypted swarm data from DHT
  Future<Map<String, dynamic>?> getEncryptedSwarmData(String infoHash) async {
    final key = '$_prefix$infoHash';
    try {
      final bytes = await _ch.invokeMethod<Uint8List>('dht_get', key);
      if (bytes == null) return null;
      return CryptoHelper.decryptJson(bytes);
    } catch (e, st) {
      debugPrint('[getEncryptedSwarmData] error: $e\n$st');
      return null;
    }
  }

  /// Get peer list from encrypted swarm object
  Future<List<dynamic>> getPeersForTorrent(String infoHash) async {
    final swarm = await getEncryptedSwarmData(infoHash);
    return swarm?['peers'] as List<dynamic>? ?? [];
  }

  /// Publish all local torrents into DHT periodically
  Future<void> broadcastLocalSwarmData() async {
    try {
      final raw = await _ch.invokeMethod<String>('getAllTorrents');
      if (raw == null || raw.isEmpty) return;

      final torrents = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      for (final t in torrents) {
        final infoHash = (t['info_hash'] ?? '').toString();
        if (infoHash.isEmpty) continue;

        await putEncryptedSwarmData(infoHash, {
          'infoHash': infoHash,
          'name': t['name'],
          'ts': DateTime.now().toIso8601String(),
        });
      }
    } catch (e, st) {
      debugPrint('[broadcastLocalSwarmData] error: $e\n$st');
    }
  }

  void dispose() {
    _broadcastTimer?.cancel();
  }
}
