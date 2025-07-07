import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

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
        // native returned JSON string, parse it
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
   *  ADD / REMOVE TORRENTS  (file‑based)    *
   *─────────────────────────────────────────*/

  /// Create a **.torrent** file on disk and return the torrent’s *name*
  /// that libtorrent reports back (usually the root folder / file name).
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

  /// Add an *existing* .torrent **file** on disk.
  ///
  /// Parameters mirror the ones you already pass from `MusicSeederService`.
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

  /// (Optional) Same as above but returns the **info‑hash** immediately if
  /// your native code provides it.  Not used by MusicSeederService right now.
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

  /// Remove a torrent by its info‑hash;  `removeData=true` wipes local files.
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

  /// Create a **.torrent file in memory** – useful if you plan to encrypt
  /// the bytes (with CryptoHelper) and share over Supabase, WebRTC, etc.
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



  /// Add a torrent directly from raw bytes (after you decrypt them).
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

  Future<String?> getInfoHashFromBytes(Uint8List bytes) async {
    try {
      final hash = await _channel.invokeMethod<String>(
        'getInfoHashFromBytes',
        bytes,
      );
      if (hash != null && hash.isNotEmpty) return hash;
    } on MissingPluginException {
      debugPrint('[LibtorrentService] ► Native infoHash not available, using fallback.');
    } catch (e, st) {
      debugPrint('[LibtorrentService] getInfoHashFromBytes failed: $e\n$st');
    }

    // Dart fallback
    final digest = sha1.convert(bytes);
    final hex    = digest.toString();
    debugPrint('[LibtorrentService] ► Fallback SHA‑1 infoHash = $hex');
    return hex;
  }

}
