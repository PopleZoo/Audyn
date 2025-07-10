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

  Future<void> startTorrentByHash(String infoHash) async {
    if (infoHash.isEmpty || infoHash.length != 40 || !RegExp(r'^[a-f0-9]+$').hasMatch(infoHash)) {
      debugPrint('[LibtorrentService] startTorrentByHash called with invalid infoHash: $infoHash');
      return;
    }

    try {
      final bool? started = await _channel.invokeMethod<bool>(
        'startTorrentByHash',
        {'infoHash': infoHash},
      );
      if (started == null || !started) {
        debugPrint('[LibtorrentService] startTorrentByHash: Failed to start torrent for hash $infoHash');
      }
    } catch (e, st) {
      debugPrint('[LibtorrentService] startTorrentByHash failed: $e\n$st');
    }
  }

}
