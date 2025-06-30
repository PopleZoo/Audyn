import 'dart:io';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../bloc/Downloads/DownloadsBloc.dart';

class LibtorrentService {
  static const MethodChannel _channel = MethodChannel('libtorrent_wrapper');

  Future<String> getVersion() async {
    try {
      return await _channel.invokeMethod('getVersion');
    } catch (e) {
      debugPrint('❌ Failed to get libtorrent version: $e');
      return 'Unknown version';
    }
  }

  /// Add torrent with swarm parameters (savePath is where downloaded content will be saved).
  /// Swarm is contained: no trackers, no DHT, no LSD.
  Future<bool> addTorrent(String torrentPath, String savePath) async {
    try {
      final result = await _channel.invokeMethod('addTorrent', {
        'torrentPath': torrentPath,
        'savePath': savePath,
        'seedMode': true,
        'announce': false,           // Disable tracker announces
        'enableDHT': false,          // Disable global DHT
        'enableLSD': false,          // Disable local service discovery (optional: true if LAN peers wanted)
        'enableUTP': true,           // Keep uTP enabled (optional)
        'enableTrackers': false,     // Disable tracker support altogether
      });
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to add torrent: $e');
      return false;
    }
  }

  Future<bool> createTorrent(String filePath, String outputPath, {List<String>? trackers}) async {
    try {
      final Map<String, dynamic> args = {
        'filePath': filePath,
        'outputPath': outputPath,
      };

      if (trackers != null && trackers.isNotEmpty) {
        args['trackers'] = trackers;
      }

      final result = await _channel.invokeMethod('createTorrent', args);
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to create torrent: $e');
      return false;
    }
  }

  Future<bool> removeTorrent(String name) async {
    try {
      final result = await _channel.invokeMethod('removeTorrent', {'name': name});
      return result == true;
    } catch (e) {
      debugPrint('❌ Failed to remove torrent: $e');
      return false;
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
      final result = await _channel.invokeMethod<String>('getSwarmInfo', {'infoHash': infoHash});
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

      // Create torrent without trackers to keep swarm contained
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
    bloc.add(StartDownload(infoHash, name));

    final documentsDir = await getApplicationDocumentsDirectory();
    final torrentPath = p.join(documentsDir.path, 'torrents', '$name.torrent');
    final added = await addTorrent(torrentPath, documentsDir.path);

    if (!added) {
      bloc.add(FailDownload(infoHash));
      return;
    }

    bool isComplete = false;
    try {
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final statsList = jsonDecode(await getTorrentStats());

        final torrentStats = (statsList as List).firstWhere(
              (e) => e['info_hash'] == infoHash,
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
}
