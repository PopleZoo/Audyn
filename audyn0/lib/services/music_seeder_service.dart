import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../src/data/services/LibtorrentService.dart';
import '../src/native/libtorrent_wrapper.dart';

String computeAudynInfoHash(String fileName) {
  final input = 'audyn_$fileName';
  return sha1.convert(utf8.encode(input)).toString();
}

class MusicSeederService {
  final OnAudioQuery audioQuery;
  final Set<String> knownHashes = {};
  late final String hashDbPath;
  late final String hashToPathMapPath;
  late final String torrentsDir;

  final Map<String, String> _hashToPathMap = {};

  Map<String, String> get hashToPathMap => _hashToPathMap;

  MusicSeederService([OnAudioQuery? audioQuery])
      : audioQuery = audioQuery ?? OnAudioQuery();

  static const List<String> allowedExtensions = ['.mp3', '.flac', '.wav', '.m4a'];

  Future<void> _initPaths() async {
    final directory = await getApplicationDocumentsDirectory();
    final basePath = directory.path;

    hashDbPath = p.join(basePath, 'known_hashes.json');
    hashToPathMapPath = p.join(basePath, 'known_hashes_map.json');
    torrentsDir = p.join(basePath, 'torrents');
  }

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

  /// Fully resets seeding state: clears local caches and deletes known files.
  Future<void> resetSeedingState() async {
    try {
      final hashFile = File(hashDbPath);
      final mapFile = File(hashToPathMapPath);

      if (await hashFile.exists()) await hashFile.delete();
      if (await mapFile.exists()) await mapFile.delete();

      knownHashes.clear();
      _hashToPathMap.clear();
      debugPrint('[Seeder] 🧼 Seeding state reset complete.');
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to reset seeding state: $e');
    }
  }

  /// Fully restart seeding:
  /// 1. Clears known hash files and maps,
  /// 2. Removes all torrents from libtorrent,
  /// 3. Resets caches,
  /// 4. Seeds local music files fresh.
  /// Fully restart seeding:
  /// 1. Ensures the service is initialized (paths ready),
  /// 2. Clears known hash files and maps,
  /// 3. Removes all torrents from libtorrent,
  /// 4. Resets caches,
  /// 5. Seeds local music files fresh.
  Future<void> restartSeeding() async {
    debugPrint('[Seeder] Starting full seeding restart...');

    // Ensure initialization done first
    await init();

    // Step 1: Reset local seeding state (delete JSON files + clear maps)
    await resetSeedingState();

    // Step 2: Remove all torrents currently loaded in libtorrent
    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();

      for (final torrent in currentTorrents) {
        final infoHash = torrent['info_hash']?.toString();
        if (infoHash == null || infoHash.isEmpty) continue;

        final removed = await LibtorrentWrapper.removeTorrentByInfoHash(infoHash);
        if (removed) {
          debugPrint('[Seeder] Removed torrent from libtorrent: $infoHash');
        } else {
          debugPrint('[Seeder] Failed to remove torrent: $infoHash');
        }
      }
    } catch (e) {
      debugPrint('[Seeder] Exception during torrent removal: $e');
    }

    // Step 3: Clear in-memory caches (redundant but safe)
    knownHashes.clear();
    _hashToPathMap.clear();

    // Step 4: Save empty caches to disk
    await _saveKnownHashes();
    await _saveHashToPathMap();

    // Step 5: Re-seed music files from scratch
    await seedMissingSongs();

    debugPrint('[Seeder] Full seeding restart complete.');
  }

  Future<void> seedMissingSongs({Duration delayBetweenAdds = const Duration(milliseconds: 200)}) async {
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
    final List<String> validFilePaths = [];

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

        final durationOk = (metadata.trackDuration != null && metadata.trackDuration! > 30 * 1000);

        if (hasAnyMetadata && durationOk) {
          validFilePaths.add(song.data);
        }
      } catch (e, st) {
        debugPrint('[Seeder] Failed to read metadata for ${song.data}: $e\n$st');
      }
    }

    await seedFiles(validFilePaths, delayBetweenAdds: delayBetweenAdds);
  }

  Future<void> seedFiles(List<String> filePaths, {Duration delayBetweenAdds = const Duration(milliseconds: 100)}) async {
    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();
      final Set<String> activeHashes = currentTorrents
          .map((t) => t['info_hash']?.toString())
          .whereType<String>()
          .toSet();

      for (final path in filePaths) {
        final file = File(path);
        if (!await file.exists()) continue;

        final title = p.basenameWithoutExtension(path);
        final safeTitle = title.replaceAll(RegExp(r"[^\w\s]"), "_");
        final torrentFilePath = p.join(torrentsDir, '$safeTitle.torrent');
        final torrentFile = File(torrentFilePath);

        try {
          if (!await torrentFile.exists()) {
            final created = await LibtorrentWrapper.createTorrent(
              path,
              torrentFilePath,
              trackers: [], // ⚠️ Optional: Remove if going trackerless
            );
            if (!created) continue;
          }

          final infoHash = await LibtorrentWrapper.getInfoHash(torrentFilePath);
          if (infoHash == null || infoHash.isEmpty) continue;

          final isKnown = knownHashes.contains(infoHash);
          final isActive = activeHashes.contains(infoHash);

          if (!isKnown || !isActive) {
            if (isKnown && !isActive) {
              knownHashes.remove(infoHash);
              _hashToPathMap.remove(infoHash);
            }

            final added = await LibtorrentWrapper.addTorrent(
              torrentFilePath,
              savePath: p.dirname(path),
              seedMode: true,
              announce: false, // P2P only
              enableDHT: false, // disable public DHT
              enableLSD: true, // local peer discovery
              enableUTP: true,
              enableTrackers: false, // disable public trackers
              enablePeerExchange: true,
            );

            if (!added) continue;

            knownHashes.add(infoHash);
            _hashToPathMap[infoHash] = path;
            await _saveKnownHashes();
            await _saveHashToPathMap();
            debugPrint('[Seeder] ✅ Seeding (P2P): $title');
            await Future.delayed(delayBetweenAdds);
          }
        } catch (e) {
          debugPrint('[Seeder] ⚠️ Error: $title\n$e');
        }
      }
    } catch (e) {
      debugPrint('[Seeder] 🚨 Torrent fetch failed: $e');
    }
  }

  Future<bool> removeTorrent(String infoHash) async {
    if (!knownHashes.contains(infoHash)) return false;

    try {
      await LibtorrentWrapper.removeTorrentByInfoHash(infoHash);

      final torrentPath = getTorrentFilePathForHash(infoHash);
      if (torrentPath != null) {
        final torrentFile = File(torrentPath);
        if (await torrentFile.exists()) await torrentFile.delete();
      }

      knownHashes.remove(infoHash);
      _hashToPathMap.remove(infoHash);

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
        knownHashes..clear()..addAll(jsonDecode(content).whereType<String>());
      } catch (e, st) {
        debugPrint('[Seeder] Failed to load known hashes: $e\n$st');
      }
    }
  }

  Future<void> _saveKnownHashes() async {
    final tempFile = File('$hashDbPath.tmp');
    await tempFile.writeAsString(jsonEncode(knownHashes.toList()));
    await tempFile.rename(hashDbPath);
  }

  Future<void> _loadHashToPathMap() async {
    final file = File(hashToPathMapPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _hashToPathMap.clear();
        _hashToPathMap.addAll(Map<String, String>.from(jsonDecode(content)));
      } catch (e, st) {
        debugPrint('[Seeder] Failed to load hash-to-path map: $e\n$st');
      }
    }
  }

  Future<void> _saveHashToPathMap() async {
    final tempFile = File('$hashToPathMapPath.tmp');
    await tempFile.writeAsString(jsonEncode(_hashToPathMap));
    await tempFile.rename(hashToPathMapPath);
  }

  String? getTorrentFilePathForHash(String infoHash) {
    if (!knownHashes.contains(infoHash)) return null;
    final title = p.basenameWithoutExtension(_hashToPathMap[infoHash] ?? infoHash);
    final safeTitle = title.replaceAll(RegExp(r"[^\w\s]"), "_");
    return p.join(torrentsDir, '$safeTitle.torrent');
  }
}
