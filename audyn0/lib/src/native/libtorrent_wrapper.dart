import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

class LibtorrentWrapper {
  static const MethodChannel _channel = MethodChannel('libtorrentwrapper');

  // Simple queue to serialize createTorrent calls
  static final List<_CreateTorrentRequest> _createTorrentQueue = [];
  static bool _isCreatingTorrent = false;

  /// Adds a torrent to the libtorrent session.
  /// Use this to join or seed Audyn P2P-only torrents.
  static Future<bool> addTorrent(
      String torrentFilePath, {
        required String savePath,
        bool seedMode = false,
        bool announce = false,
        bool enableDHT = true,
        bool enableLSD = true,
        bool enableUTP = true,
        bool enableTrackers = false,
        bool enablePeerExchange = true,
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

  /// Adds a torrent from raw torrent file bytes directly.
  static Future<bool> addTorrentFromBytes(
      Uint8List torrentBytes, {
        required String savePath,
        bool seedMode = false,
        bool announce = false,
        bool enableDHT = true,
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
  /// This method queues requests to avoid concurrency issues in native code.
  static Future<bool> createTorrent(
      String path,
      String torrentFilePath, {
        List<String>? trackers,
      }) {
    final completer = Completer<bool>();

    _createTorrentQueue.add(
      _CreateTorrentRequest(
        path,
        torrentFilePath,
        trackers ?? [],
        completer,
      ),
    );

    _processCreateTorrentQueue();

    return completer.future;
  }

  // Process the createTorrent queue one at a time
  static void _processCreateTorrentQueue() {
    if (_isCreatingTorrent || _createTorrentQueue.isEmpty) return;

    _isCreatingTorrent = true;
    final request = _createTorrentQueue.removeAt(0);

    final args = {
      'filePath': request.path,
      'outputPath': request.outputPath,
      'trackers': request.trackers,
    };

    _channel.invokeMethod<bool>('createTorrent', args).then((result) {
      request.completer.complete(result == true);
    }).catchError((e, stacktrace) {
      debugPrint('[LibtorrentWrapper] createTorrent error: $e\n$stacktrace');
      request.completer.complete(false);
    }).whenComplete(() {
      _isCreatingTorrent = false;
      // Process next request in queue
      _processCreateTorrentQueue();
    });
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

  /// Retrieves swarm info for a given infoHash.
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

  /// Get the save path for a torrent by its infoHash.
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

class _CreateTorrentRequest {
  final String path;
  final String outputPath;
  final List<String> trackers;
  final Completer<bool> completer;

  _CreateTorrentRequest(this.path, this.outputPath, this.trackers, this.completer);
}
