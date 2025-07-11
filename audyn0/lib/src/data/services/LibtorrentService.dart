import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// A thin, Flutter‑side wrapper around the native libtorrent bridge.
/// All heavy work happens in the platform (Android / iOS / desktop) code.
///
/// Make sure the same method names exist in your MethodChannel handler
/// on the native side, otherwise you’ll get a `MissingPluginException`.
class LibtorrentService {
  static const MethodChannel _channel = MethodChannel('libtorrentwrapper');

  /*─────────────────────────────────────────*
   *  QUERY / SESSION HELPERS                *
   *─────────────────────────────────────────*/

  Future<List<Map<String, dynamic>>> getAllTorrents() async {
    try {
      final dynamic raw = await _channel.invokeMethod('getAllTorrents');
      if (raw is String) {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed.cast<Map<String, dynamic>>();
        }
        return [];
      } else if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
      }
      return [];
    } catch (e, st) {
      debugPrint('[LibtorrentService] getAllTorrents failed: $e\n$st');
      return [];
    }
  }

  /*─────────────────────────────────────────*
   *  ADD / REMOVE TORRENTS  (file‑based)    *
   *─────────────────────────────────────────*/

  Future<String?> createTorrentAndGetName(
      String sourcePath,
      String outputDir,
      ) async {
    try {
      final name = await _channel.invokeMethod<String>(
        'createTorrentAndGetName',
        {
          'sourcePath': sourcePath,
          'outputDir': outputDir,
        },
      );
      return name;
    } catch (e, st) {
      debugPrint('[LibtorrentService] createTorrentAndGetName failed: $e\n$st');
      return null;
    }
  }

  Future<bool> addTorrent(
      String torrentFilePath,
      String savePath, {
        bool seedMode = true,
        bool announce = false,
        bool enableDHT = true,
        bool enableLSD = true,
        bool enableUTP = true,
        bool enableTrackers = false,
        bool enablePeerExchange = true,
      }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('addTorrent', {
        'torrentFilePath': torrentFilePath,
        'savePath': savePath,
        'seedMode': seedMode,
        'announce': announce,
        'enableDHT': enableDHT,
        'enableLSD': enableLSD,
        'enableUTP': enableUTP,
        'enableTrackers': enableTrackers,
        'enablePeerExchange': enablePeerExchange,
      });
      return ok ?? false;
    } catch (e, st) {
      debugPrint('[LibtorrentService] addTorrent failed: $e\n$st');
      return false;
    }
  }

  Future<String?> addTorrentAndGetInfoHash(
      String torrentFilePath,
      String savePath, {
        bool seedMode = false,
        bool announce = false,
      }) async {
    try {
      final hash = await _channel.invokeMethod<String>('addTorrentReturnHash', {
        'torrentFilePath': torrentFilePath,
        'savePath': savePath,
        'seedMode': seedMode,
        'announce': announce,
      });
      return hash;
    } catch (e, st) {
      debugPrint('[LibtorrentService] addTorrentAndGetInfoHash failed: $e\n$st');
      return null;
    }
  }

  Future<bool> removeTorrent(String infoHash, {bool removeData = false}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('removeTorrent', {
        'infoHash': infoHash,
        'removeData': removeData,
      });
      return ok ?? false;
    } catch (e, st) {
      debugPrint('[LibtorrentService] removeTorrent failed: $e\n$st');
      return false;
    }
  }

  /*─────────────────────────────────────────*
   *  (OPTIONAL)  BYTE‑BASED ADD / EXPORT    *
   *─────────────────────────────────────────*/

  Future<Uint8List?> createTorrentBytes(String sourcePath) async {
    try {
      print('[DEBUG] Calling native createTorrentBytes($sourcePath)');
      final result = await _channel.invokeMethod<Uint8List>(
        'createTorrentBytes',
        {'sourcePath': sourcePath},
      );
      print('[DEBUG] Got result: ${result?.length ?? "null"} bytes');
      return result;
    } catch (e, st) {
      print('[DEBUG] Native error: $e\n$st');
      return null;
    }
  }

  Future<bool> addTorrentFromBytes(
      Uint8List torrentBytes,
      String savePath, {
        bool seedMode = false,
        bool announce = false,
      }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('addTorrentFromBytes', {
        'torrentBytes': torrentBytes,
        'savePath': savePath,
        'seedMode': seedMode,
        'announce': announce,
      });
      return ok ?? false;
    } catch (e, st) {
      debugPrint('[LibtorrentService] addTorrentFromBytes failed: $e\n$st');
      return false;
    }
  }

  /// NEW DIRECT METHOD: Get infoHash from raw .torrent bytes without writing to file.
  Future<String?> getInfoHashFromDecryptedBytes(Uint8List torrentBytes) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getInfoHashFromDecryptedBytes',
        {
          'torrentBytes': torrentBytes,
        },
      );

      if (result == null || result.trim().isEmpty) {
        debugPrint('[LibtorrentService] ► Native infoHash not available, using fallback.');
        final fallback = sha1.convert(torrentBytes).toString();
        debugPrint('[LibtorrentService] ► Fallback SHA‑1 infoHash = $fallback');
        return fallback;
      }

      return result.trim();
    } catch (e, st) {
      debugPrint('[LibtorrentService] getInfoHashFromDecryptedBytes error: $e\n$st');
      return null;
    }
  }




  Future<List<Map<String, dynamic>>> getTorrentList({
    required Future<Map<String, dynamic>?> Function(String torrentName) metadataFetcher,
  }) async {
    final torrents = await getAllTorrents();

    List<Map<String, dynamic>> enriched = [];
    for (final torrent in torrents) {
      final name = torrent['name']?.toString() ?? '';
      if (name.isEmpty) {
        enriched.add(torrent);
        continue;
      }

      final metadata = await metadataFetcher(name);
      if (metadata != null) {
        enriched.add({
          ...torrent,
          ...metadata,
        });
      } else {
        enriched.add(torrent);
      }
    }

    return enriched;
  }

  Future<bool> isTorrentActive(String infoHash) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'isTorrentActive',
        {'infoHash': infoHash},
      );
      return result ?? false;
    } catch (e, st) {
      debugPrint('[LibtorrentService] isTorrentActive failed: $e\n$st');
      return false;
    }
  }

  Future<void> startTorrentByHash(String? infoHash) async {
    if (infoHash == null || infoHash.isEmpty) {
      debugPrint('[LibtorrentService] ❌ startTorrentByHash: infoHash is null or empty');
      return;
    }

    // Validate length and format (40-char lowercase hex string)
    final isValidHash = RegExp(r'^[a-f0-9]{40}$').hasMatch(infoHash);
    if (!isValidHash) {
      debugPrint('[LibtorrentService] ❌ startTorrentByHash: invalid format for infoHash: "$infoHash"');
      return;
    }

    try {
      final bool? started = await _channel.invokeMethod<bool>(
        'startTorrentByHash',
        {'infoHash': infoHash},
      );

      if (started == true) {
        debugPrint('[LibtorrentService] ✅ Torrent started for hash: $infoHash');
      } else {
        debugPrint('[LibtorrentService] ⚠️ Torrent not started (null or false) for hash: $infoHash');
      }
    } catch (e, st) {
      debugPrint('[LibtorrentService] 🧨 startTorrentByHash threw exception: $e\n$st');
    }
  }

  Future<void> startOrRestartTorrentByHash(String infoHash) async {
    final isRunning = await isTorrentRunning(infoHash);

    if (isRunning) {
      final isHealthy = await isTorrentHealthy(infoHash);
      if (!isHealthy) {
        debugPrint('[LibtorrentService] ⚠️ Torrent $infoHash is stale, removing and re-adding');
        await removeTorrent(infoHash, removeData: false);
        await addTorrentByHash(infoHash);
      } else {
        debugPrint('[LibtorrentService] ✅ Torrent $infoHash is already running and healthy');
      }
    } else {
      await addTorrentByHash(infoHash);
      debugPrint('[LibtorrentService] ▶️ Torrent $infoHash added and started');
    }
  }
  /// Checks if a torrent with the given infoHash is currently running
  Future<bool> isTorrentRunning(String infoHash) async {
    try {
      final torrents = await getAllTorrents();
      return torrents.any((t) => t['infoHash'] == infoHash);
    } catch (e, st) {
      debugPrint('[LibtorrentService] isTorrentRunning failed: $e\n$st');
      return false;
    }
  }

  /// Basic health check — expand this based on your criteria
  /// For now, returns true if torrent has at least 1 peer or is seeding
  Future<bool> isTorrentHealthy(String infoHash) async {
    try {
      final torrents = await getAllTorrents();
      final torrent = torrents.firstWhere(
            (t) => t['infoHash'] == infoHash,
        orElse: () => {},
      );

      final peers = int.tryParse('${torrent['numPeers'] ?? 0}') ?? 0;
      final progress = double.tryParse('${torrent['progress'] ?? 0.0}') ?? 0.0;

      // Example criteria: has peers or is nearly complete
      return peers > 0 || progress >= 0.95;
    } catch (e, st) {
      debugPrint('[LibtorrentService] isTorrentHealthy failed: $e\n$st');
      return false;
    }
  }

  /// Re-adds torrent from known local .torrent file by hash
  Future<void> addTorrentByHash(String infoHash) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final torrentPath = p.join(dir.path, 'torrents', '$infoHash.torrent');
      final savePath = p.join(dir.path, 'downloads', infoHash);

      final exists = await File(torrentPath).exists();
      if (!exists) {
        debugPrint('[LibtorrentService] ❌ Torrent file missing: $torrentPath');
        return;
      }

      final success = await addTorrent(torrentPath, savePath);
      if (success) {
        debugPrint('[LibtorrentService] ✅ Re-added torrent for $infoHash');
      } else {
        debugPrint('[LibtorrentService] ❌ Failed to re-add torrent for $infoHash');
      }
    } catch (e, st) {
      debugPrint('[LibtorrentService] addTorrentByHash failed: $e\n$st');
    }
  }

  Future<void> stopTorrentByHash(String infoHash) async {
    if (infoHash.isEmpty) return;

    try {
      final bool? stopped = await _channel.invokeMethod<bool>(
        'stopTorrentByHash',
        {'infoHash': infoHash},
      );

      if (stopped == true) {
        debugPrint('[LibtorrentService] 🛑 Torrent stopped for hash: $infoHash');
      } else {
        debugPrint('[LibtorrentService] ⚠️ Torrent not stopped for hash: $infoHash');
      }
    } catch (e, st) {
      debugPrint('[LibtorrentService] stopTorrentByHash threw: $e\n$st');
    }
  }

  /// Returns all locally stored .torrent.enc files (used for cleanup)
  Future<List<File>> getAllLocalTorrentFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final torrentsDir = Directory(p.join(dir.path, 'torrents'));
      if (!await torrentsDir.exists()) return [];

      return torrentsDir
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.torrent.enc'))
          .toList();
    } catch (e, st) {
      debugPrint('[LibtorrentService] getAllLocalTorrentFiles failed: $e\n$st');
      return [];
    }
  }


}
