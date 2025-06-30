import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../src/data/services/LibtorrentService.dart';
import '../src/native/libtorrent_wrapper.dart';

class MusicSeederService {
  final OnAudioQuery audioQuery;
  final Set<String> knownHashes = {};
  late final String hashDbPath;
  late final String hashToPathMapPath;
  late final String torrentsDir;

  Map<String, String> _hashToPathMap = {};

  /// Public getter to expose infoHash → file path mapping
  Map<String, String> get hashToPathMap => _hashToPathMap;

  MusicSeederService([OnAudioQuery? audioQuery])
      : audioQuery = audioQuery ?? OnAudioQuery();

  /// Initializes directory paths and loads stored data.
  Future<void> init() async {
    await _initPaths();
    await _loadKnownHashes();
    await _loadHashToPathMap();

    final dir = Directory(torrentsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[Seeder] Created torrents directory at $torrentsDir');
    }
  }

  Future<void> _initPaths() async {
    final directory = await getApplicationDocumentsDirectory();
    final basePath = directory.path;

    hashDbPath = p.join(basePath, 'known_hashes.json');
    hashToPathMapPath = p.join(basePath, 'known_hashes_map.json');
    torrentsDir = p.join(basePath, 'torrents');
  }

  /// Deletes stored seeding info and resets internal state.
  Future<void> resetSeedingState() async {
    try {
      final hashFile = File(hashDbPath);
      final mapFile = File(hashToPathMapPath);

      if (await hashFile.exists()) {
        await hashFile.delete();
        debugPrint('[Seeder] 🔄 Deleted known_hashes.json');
      }

      if (await mapFile.exists()) {
        await mapFile.delete();
        debugPrint('[Seeder] 🔄 Deleted known_hashes_map.json');
      }

      knownHashes.clear();
      _hashToPathMap.clear();
      debugPrint('[Seeder] 🧼 Seeding state reset complete.');
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to reset seeding state: $e');
    }
  }

  /// Queries device music library and seeds valid songs.
  /// Optional delay between adding torrents to avoid overwhelming resources.
  Future<void> seedMissingSongs({Duration delayBetweenAdds = const Duration(milliseconds: 200)}) async {
    // NOTE: In background isolate, audioQuery permission may not be available
    // So check and skip if no permission or audioQuery not initialized.

    try {
      final permission = await audioQuery.permissionsStatus();
      if (!permission) {
        debugPrint('[Seeder] Permission to query audio not granted. Skipping seeding.');
        return;
      }
    } catch (e) {
      debugPrint('[Seeder] Unable to check audio permission: $e');
      return;
    }

    final List<SongModel> allSongs = await audioQuery.querySongs();
    const allowedExtensions = ['.mp3', '.flac', '.wav', '.m4a'];
    final List<String> validFilePaths = [];

    debugPrint('[Seeder] 🔍 Filtering ${allSongs.length} total files...');

    for (final song in allSongs) {
      final ext = p.extension(song.data).toLowerCase();

      if (!(song.isMusic == true && allowedExtensions.contains(ext))) continue;

      final file = File(song.data);
      if (!await file.exists()) continue;

      try {
        final metadata = await MetadataRetriever.fromFile(file);

        final hasAnyMetadata = (metadata.trackName?.trim().isNotEmpty ?? false) ||
            (metadata.authorName?.trim().isNotEmpty ?? false) ||
            (metadata.albumName?.trim().isNotEmpty ?? false);

        final durationOk = (metadata.trackDuration != null && metadata.trackDuration! > 30 * 1000); // > 30s

        if (hasAnyMetadata && durationOk) {
          validFilePaths.add(song.data);
          debugPrint('[Seeder] ✅ Valid song: ${metadata.trackName ?? song.title} - ${metadata.authorName ?? "Unknown"}');
        } else {
          debugPrint('[Seeder] ⚠️ Skipping: Incomplete metadata or short duration - ${song.title}');
        }
      } catch (e) {
        debugPrint('[Seeder] ⚠️ Failed to read metadata for: ${song.data}\n$e');
      }
    }

    debugPrint('[Seeder] 🎶 ${validFilePaths.length} valid songs to seed.');
    await seedFiles(validFilePaths, delayBetweenAdds: delayBetweenAdds);
  }

  /// Seeds the given list of file paths by creating & adding torrents if needed.
  Future<void> seedFiles(
      List<String> filePaths, {
        Duration delayBetweenAdds = const Duration(milliseconds: 100),
      }) async {
    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();
      final Set<String> activeHashes = currentTorrents
          .map((t) => t['info_hash']?.toString())
          .whereType<String>()
          .toSet();

      // --- CLEANUP stale torrents (file missing & only 1 seeder) ---
      for (final t in currentTorrents) {
        final infoHash = t['info_hash']?.toString();
        if (infoHash == null) continue;

        final filePath = _hashToPathMap[infoHash];
        final fileExists = filePath != null ? await File(filePath).exists() : false;
        final seeders = t['seeders'] ?? 0;

        if (!fileExists && seeders == 1 && knownHashes.contains(infoHash)) {
          // Remove stale torrent
          debugPrint('[Seeder] 🧹 Removing stale torrent with no file and single seeder: $infoHash');

          // Remove from known lists
          knownHashes.remove(infoHash);
          _hashToPathMap.remove(infoHash);

          // Delete torrent file if exists
          final torrentPath = getTorrentFilePathForHash(infoHash);
          if (torrentPath != null) {
            final torrentFile = File(torrentPath);
            if (await torrentFile.exists()) {
              await torrentFile.delete();
              debugPrint('[Seeder] Deleted torrent file at $torrentPath');
            }
          }

          // Remove torrent from libtorrent swarm
          await LibtorrentWrapper.removeTorrentByInfoHash(infoHash);

          // Save updated maps
          await _saveKnownHashes();
          await _saveHashToPathMap();
        }
      }

      for (final path in filePaths) {
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('[Seeder] ❌ File missing: $path');
          continue;
        }

        final title = p.basenameWithoutExtension(path);
        final safeTitle = title.replaceAll(RegExp(r"[^\w\s]"), "_");
        final torrentFilePath = p.join(torrentsDir, '$safeTitle.torrent');
        final torrentFile = File(torrentFilePath);

        try {
          // 🌀 Step 1: Create torrent if not yet created
          if (!await torrentFile.exists()) {
            final created = await LibtorrentWrapper.createTorrent(
              path,
              torrentFilePath,
              trackers: [
                'udp://tracker.opentrackr.org:1337/announce',
                'udp://tracker.openbittorrent.com:80/announce',
                'udp://tracker.leechers-paradise.org:6969/announce',
                'udp://explodie.org:6969/announce',
                'udp://tracker.coppersurfer.tk:6969/announce',
              ],
            );
            if (!created) {
              debugPrint('[Seeder] ❌ Failed to create .torrent: $title');
              continue;
            }
          }

          // 🌀 Step 2: Get infoHash from .torrent
          final infoHash = await LibtorrentWrapper.getInfoHash(torrentFilePath);
          if (infoHash == null || infoHash.isEmpty) {
            debugPrint('[Seeder] ❌ Invalid info_hash: $title');
            continue;
          }

          // 🌀 Step 3: Check if known or active
          final isKnown = knownHashes.contains(infoHash);
          final isActive = activeHashes.contains(infoHash);

          if (!isKnown || !isActive) {
            if (isKnown && !isActive) {
              knownHashes.remove(infoHash);
              _hashToPathMap.remove(infoHash);
              debugPrint('[Seeder] 🧹 Removed stale: $title');
            }

            // 🌀 Step 4: Add torrent to swarm with full seeding config
            final added = await LibtorrentWrapper.addTorrent(
              torrentFilePath,
              savePath: p.dirname(path),
              seedMode: true,
              announce: true,
              enableDHT: true,
              enableLSD: true,
              enableUTP: true,
              enableTrackers: true,
            );

            if (!added) {
              debugPrint('[Seeder] ❌ Failed to add to swarm: $title');
              continue;
            }

            knownHashes.add(infoHash);
            _hashToPathMap[infoHash] = path;
            await _saveKnownHashes();
            await _saveHashToPathMap();

            debugPrint('[Seeder] ✅ Seeding: $title');
            await Future.delayed(delayBetweenAdds);
          } else {
            debugPrint('[Seeder] 🔁 Already active: $title');
          }
        } catch (e) {
          debugPrint('[Seeder] ⚠️ Error: $title\n$e');
        }
      }
    } catch (e) {
      debugPrint('[Seeder] 🚨 Failed to fetch current torrents: $e');
    }
  }

  Future<bool> removeTorrent(String infoHash) async {
    if (!knownHashes.contains(infoHash)) return false;

    try {
      // Remove torrent from libtorrent swarm
      await LibtorrentWrapper.removeTorrentByInfoHash(infoHash);

      // Delete .torrent file if exists
      final torrentPath = getTorrentFilePathForHash(infoHash);
      if (torrentPath != null) {
        final torrentFile = File(torrentPath);
        if (await torrentFile.exists()) {
          await torrentFile.delete();
        }
      }

      // Remove from known hashes and map
      knownHashes.remove(infoHash);
      _hashToPathMap.remove(infoHash);

      // Save updated state
      await _saveKnownHashes();
      await _saveHashToPathMap();

      debugPrint('[Seeder] Removed torrent: $infoHash');
      return true;
    } catch (e) {
      debugPrint('[Seeder] Failed to remove torrent: $e');
      return false;
    }
  }


  Future<void> _loadKnownHashes() async {
    final file = File(hashDbPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        knownHashes
          ..clear()
          ..addAll(jsonList.whereType<String>());
        debugPrint('[Seeder] Loaded ${knownHashes.length} known hashes.');
      } catch (e) {
        debugPrint('[Seeder] ⚠️ Failed to load known hashes: $e');
      }
    }
  }

  Future<void> _saveKnownHashes() async {
    final file = File(hashDbPath);
    try {
      await file.writeAsString(jsonEncode(knownHashes.toList()));
      debugPrint('[Seeder] Saved ${knownHashes.length} known hashes.');
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to save known hashes: $e');
    }
  }

  Future<void> _loadHashToPathMap() async {
    final file = File(hashToPathMapPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final Map<String, dynamic> decoded = jsonDecode(content);
        _hashToPathMap = decoded.map((key, value) => MapEntry(key, value.toString()));
        debugPrint('[Seeder] Loaded hash→path map with ${_hashToPathMap.length} entries.');
      } catch (e) {
        debugPrint('[Seeder] ⚠️ Failed to load hash→path map: $e');
      }
    }
  }

  Future<void> _saveHashToPathMap() async {
    final file = File(hashToPathMapPath);
    try {
      await file.writeAsString(jsonEncode(_hashToPathMap));
      debugPrint('[Seeder] Saved hash→path map with ${_hashToPathMap.length} entries.');
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to save hash→path map: $e');
    }
  }

  /// Returns the .torrent file path associated with an infoHash, or null if unknown.
  String? getTorrentFilePathForHash(String infoHash) {
    if (!knownHashes.contains(infoHash)) return null;
    final title = p.basenameWithoutExtension(_hashToPathMap[infoHash] ?? infoHash);
    final safeTitle = title.replaceAll(RegExp(r"[^\w\s]"), "_");
    return p.join(torrentsDir, '$safeTitle.torrent');
  }
}
