import 'dart:io';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../bloc/Downloads/DownloadsBloc.dart';
import '../../native/libtorrent_wrapper.dart';

class LibtorrentService {
  static const MethodChannel _channel = MethodChannel('libtorrent_wrapper');

  Future<String> getVersion() async {
    try {
      final result = await _channel.invokeMethod<String>('getVersion');
      return result ?? 'Unknown version';
    } catch (e) {
      debugPrint('❌ Failed to get libtorrent version: $e');
      return 'Unknown version';
    }
  }

  Future<bool> addTorrent(
      String filePath,
      String savePath, {
        bool seedMode = true,
        bool announce = false,
        bool enableDHT = false,
        bool enableLSD = false,
        bool enableUTP = true,
        bool enableTrackers = false,
        bool enablePeerExchange = true,
      }) async {
    try {
      final result = await _channel.invokeMethod('addTorrent', {
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
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to add torrent: $e');
      return false;
    }
  }

  Future<bool> createTorrent(
      String filePath,
      String outputPath, {
        List<String>? trackers,
      }) async {
    try {
      final args = {
        'filePath': filePath,
        'outputPath': outputPath,
        if (trackers != null && trackers.isNotEmpty) 'trackers': trackers,
      };

      final result = await _channel.invokeMethod('createTorrent', args);
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to create torrent: $e');
      return false;
    }
  }

  Future<bool> removeTorrent(String infoHash) async {
    try {
      final result = await _channel.invokeMethod('removeTorrentByInfoHash', {
        'infoHash': infoHash,
      });
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to remove torrent: $e');
      return false;
    }
  }

  Future<void> cleanupSession() async {
    try {
      await _channel.invokeMethod('cleanupSession');
    } catch (e) {
      debugPrint('❌ Failed to clean up session: $e');
    }
  }

  Future<String> getTorrentStats() async {
    try {
      final result = await _channel.invokeMethod<String>('getTorrentStats');
      return result ?? '[]';
    } catch (e) {
      debugPrint('❌ Failed to get torrent stats: $e');
      return '[]';
    }
  }

  Future<String> getSwarmInfo(String infoHash) async {
    try {
      // Pass raw string, not Map
      final result = await _channel.invokeMethod<String>('getSwarmInfo', infoHash);
      return result ?? '{}';
    } catch (e) {
      debugPrint('❌ Failed to get swarm info: $e');
      return '{}';
    }
  }

  Future<List<dynamic>> getPeersForTorrent(String infoHash) async {
    try {
      final swarmInfoJson = await getSwarmInfo(infoHash);
      final Map<String, dynamic> swarmInfo = jsonDecode(swarmInfoJson);
      return swarmInfo['peers'] ?? [];
    } catch (e) {
      debugPrint('❌ Failed to get peers for torrent: $e');
      return [];
    }
  }

  String _cleanTitle(String input) {
    return input
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'[_\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  Future<List<Map<String, dynamic>>> getAllTorrents() async {
    try {
      final jsonString = await _channel.invokeMethod<String>('getAllTorrents');
      if (jsonString == null || jsonString.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Failed to get all torrents: $e');
      return [];
    }
  }

  Future<bool> _isSongValid(String title, String artist) async {
    final cleanedTitle = _cleanTitle(title);
    final cleanedArtist = artist.trim().toLowerCase();

    final query = Uri.https('musicbrainz.org', '/ws/2/recording', {
      'query': 'recording:$cleanedTitle AND artist:$cleanedArtist',
      'fmt': 'json',
    });

    try {
      final response = await http.get(query, headers: {
        'User-Agent': 'Audyn/1.0 (you@example.com)',
      });

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final recordings = data['recordings'] as List<dynamic>?;

      if (recordings == null || recordings.isEmpty) return false;

      return recordings.any((r) {
        final recTitle = _cleanTitle(r['title'] ?? '');
        final recArtists = (r['artist-credit'] as List?)
            ?.map((e) => (e['name'] ?? '').toString().toLowerCase())
            .toList();

        return recTitle.contains(cleanedTitle) &&
            (recArtists?.any((a) => a.contains(cleanedArtist)) ?? false);
      });
    } catch (e) {
      debugPrint('❌ MusicBrainz API error: $e');
      return false;
    }
  }

  Future<bool> addSongToSwarm(String songPath, {String? title, String? artist}) async {
    try {
      final file = File(songPath);
      if (!await file.exists()) return false;

      final fileName = p.basenameWithoutExtension(songPath);
      final songTitle = title ?? fileName;
      final songArtist = artist ?? '';

      final valid = await _isSongValid(songTitle, songArtist);
      if (!valid) return false;

      final tempDir = await getTemporaryDirectory();
      final torrentPath = p.join(tempDir.path, '$fileName.torrent');

      final created = await createTorrent(songPath, torrentPath, trackers: []);
      if (!created) return false;

      final added = await addTorrent(torrentPath, p.dirname(songPath));

      try {
        await File(torrentPath).delete();
      } catch (_) {}

      return added;
    } catch (e) {
      debugPrint('❌ Error adding song to swarm: $e');
      return false;
    }
  }

  Future<String?> _recursiveSearchForFile(Directory dir, String targetName) async {
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && p.basename(entity.path).toLowerCase() == targetName.toLowerCase()) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getFilePathForTorrent(Map<String, dynamic> torrent) async {
    try {
      final infoHash = torrent['info_hash'];
      final name = torrent['name'];

      final documentsDir = await getApplicationDocumentsDirectory();
      final mapFile = File(p.join(documentsDir.path, 'known_hashes_map.json'));

      if (await mapFile.exists()) {
        final map = jsonDecode(await mapFile.readAsString());
        final path = map[infoHash];
        if (path != null && await File(path).exists()) return path;
      }

      final searchDirs = [
        Directory('/storage/emulated/0/Music'),
        Directory('/storage/emulated/0/Download'),
        if (Platform.isAndroid) await getDownloadsDirectory() ?? Directory(''),
        documentsDir,
      ];

      for (final dir in searchDirs) {
        if (!await dir.exists()) continue;
        final found = await _recursiveSearchForFile(dir, name);
        if (found != null) return found;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error resolving file path for torrent: $e');
      return null;
    }
  }

  Future<void> downloadTorrent(BuildContext context, Map<String, dynamic> t) async {
    final infoHash = t['info_hash'] ?? '';
    final name = t['name'] ?? 'unknown';

    if (infoHash.isEmpty || name.isEmpty) return;

    final bloc = context.read<DownloadsBloc>();

    // TODO: You must supply destinationFolder and playlist when starting download.
    // Here we use documents directory as destination and empty playlist for example.
    final documentsDir = await getApplicationDocumentsDirectory();
    final destinationFolder = documentsDir.path;
    final playlist = <String>[]; // replace with actual playlist IDs or names if available

    bloc.add(StartDownload(
      infoHash: infoHash,
      name: name,
      destinationFolder: destinationFolder,
      playlist: playlist,
    ));

    final torrentPath = p.join(documentsDir.path, 'torrents', '$name.torrent');
    final added = await addTorrent(torrentPath, destinationFolder);

    if (!added) {
      bloc.add(FailDownload(infoHash));
      return;
    }

    bool isComplete = false;
    try {
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final statsListRaw = await getTorrentStats();

        final statsList = jsonDecode(statsListRaw) as List;
        final torrentStats = statsList.firstWhere(
              (e) => (e['info_hash'] == infoHash) || (e['name'] == name),
          orElse: () => null,
        );

        final progress = (torrentStats?['progress'] ?? 0.0).toDouble();
        bloc.add(UpdateDownloadProgress(infoHash, progress));

        if (progress >= 0.99) {
          isComplete = true;
          break;
        }
      }
    } catch (e) {
      debugPrint('❌ Error polling torrent progress: $e');
    }

    if (!isComplete) {
      bloc.add(FailDownload(infoHash));
      return;
    }

    final filePath = await getFilePathForTorrent(t);
    if (filePath == null || !(await File(filePath).exists())) {
      bloc.add(FailDownload(infoHash));
      return;
    }

    bloc.add(CompleteDownload(infoHash, filePath));
  }

  Future<Map<String, dynamic>?> getTorrentMetadata(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<String>('getTorrentMetadata', infoHash);
      if (result == null || result.isEmpty) return null;
      return jsonDecode(result) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ Failed to get torrent metadata: $e');
      return null;
    }
  }

  Future<String?> getTorrentSavePath(String infoHash) async {
    try {
      final result = await _channel.invokeMethod<String>('getTorrentSavePath', infoHash);
      return (result != null && result.isNotEmpty) ? result : null;
    } catch (e) {
      debugPrint('❌ Failed to get torrent save path: $e');
      return null;
    }
  }

  static Future<Uint8List?> getTorrentFileByHash(String infoHash) async {
    // For example, load the torrent file from your local torrents folder:
    try {
      final torrentsDir = await getApplicationDocumentsDirectory();
      final path = p.join(torrentsDir.path, 'torrents', '$infoHash.torrent');
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      } else {
        debugPrint('[LibtorrentService] Torrent file not found for hash $infoHash at $path');
        return null;
      }
    } catch (e) {
      debugPrint('[LibtorrentService] Error reading torrent file for $infoHash: $e');
      return null;
    }
  }

  Future<bool> addTorrentFromBytes(Uint8List torrentBytes, {required String savePath}) async {
    try {
      final result = await LibtorrentWrapper.addTorrentFromBytes(
        torrentBytes,
        savePath: savePath,  // <-- Pass the required save path here
        seedMode: true,      // Optional, adjust flags as needed
        announce: false,
        enableDHT: false,
        enableLSD: true,
        enableUTP: true,
        enableTrackers: false,
        enablePeerExchange: true,
      );
      return result == true;
    } catch (e) {
      debugPrint('[LibtorrentService] Failed to add torrent from bytes: $e');
      return false;
    }
  }

}
