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
  final hash = sha1.convert(utf8.encode(input)).toString();
  debugPrint('[computeAudynInfoHash] Input: $input, Hash: $hash');
  return hash;
}

class MusicSeederService {
  final OnAudioQuery audioQuery;
  final Set<String> knownHashes = {};
  late final String hashDbPath;
  late final String hashToPathMapPath;
  late final String torrentsDir;

  final Map<String, String> _hashToPathMap = {};

  // Cache metadata per infoHash to avoid repeated file reads
  final Map<String, Map<String, dynamic>?> _metadataCache = {};

  Map<String, String> get hashToPathMap => _hashToPathMap;

  MusicSeederService([OnAudioQuery? audioQuery])
      : audioQuery = audioQuery ?? OnAudioQuery() {
    debugPrint('[MusicSeederService] Constructor called');
  }

  static const List<String> allowedExtensions = [
    '.mp3',
    '.flac',
    '.wav',
    '.m4a'
  ];

  Future<void> _initPaths() async {
    final directory = await getApplicationDocumentsDirectory();
    final basePath = directory.path;
    debugPrint('[Seeder] Application documents directory: $basePath');

    hashDbPath = p.join(basePath, 'known_hashes.json');
    hashToPathMapPath = p.join(basePath, 'known_hashes_map.json');
    torrentsDir = p.join(basePath, 'torrents');

    debugPrint('[Seeder] Paths initialized:');
    debugPrint('  knownHashes path: $hashDbPath');
    debugPrint('  hashToPathMap path: $hashToPathMapPath');
    debugPrint('  torrents directory: $torrentsDir');
  }

  Future<void> init() async {
    debugPrint('[Seeder] Initializing MusicSeederService...');
    await _initPaths();
    await _loadKnownHashes();
    await _loadHashToPathMap();

    final dir = Directory(torrentsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[Seeder] Created torrents directory at $torrentsDir');
    } else {
      debugPrint('[Seeder] Torrents directory already exists at $torrentsDir');
    }
    debugPrint('[Seeder] Initialization complete.');
  }

  Future<void> resetSeedingState() async {
    debugPrint('[Seeder] Resetting seeding state...');
    try {
      final hashFile = File(hashDbPath);
      final mapFile = File(hashToPathMapPath);

      if (await hashFile.exists()) {
        await hashFile.delete();
        debugPrint('[Seeder] Deleted known hashes file');
      } else {
        debugPrint('[Seeder] Known hashes file not found');
      }

      if (await mapFile.exists()) {
        await mapFile.delete();
        debugPrint('[Seeder] Deleted hash-to-path map file');
      } else {
        debugPrint('[Seeder] Hash-to-path map file not found');
      }

      knownHashes.clear();
      _hashToPathMap.clear();
      _metadataCache.clear();
      debugPrint('[Seeder] 🧼 Seeding state reset complete.');
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to reset seeding state: $e');
    }
  }

  Future<void> restartSeeding() async {
    debugPrint('[Seeder] Starting full seeding restart...');
    await init();

    debugPrint('[Seeder] Step 1: Resetting local seeding state');
    await resetSeedingState();

    debugPrint('[Seeder] Step 2: Removing all torrents from libtorrent');
    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      debugPrint('[Seeder] Torrent stats received: $rawStats');

      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();

      for (final torrent in currentTorrents) {
        final infoHash = torrent['info_hash']?.toString();
        if (infoHash == null || infoHash.isEmpty) {
          debugPrint('[Seeder] Skipping torrent with null/empty info_hash');
          continue;
        }
        final removed = await LibtorrentWrapper.removeTorrentByInfoHash(
            infoHash);
        if (removed) {
          debugPrint('[Seeder] Removed torrent from libtorrent: $infoHash');
        } else {
          debugPrint('[Seeder] Failed to remove torrent: $infoHash');
        }
      }
    } catch (e) {
      debugPrint('[Seeder] Exception during torrent removal: $e');
    }

    debugPrint('[Seeder] Step 3: Clearing in-memory caches');
    knownHashes.clear();
    _hashToPathMap.clear();
    _metadataCache.clear();

    debugPrint('[Seeder] Step 4: Saving empty caches to disk');
    await _saveKnownHashes();
    await _saveHashToPathMap();

    debugPrint('[Seeder] Step 5: Seeding missing songs from device');
    await seedMissingSongs();

    debugPrint('[Seeder] Full seeding restart complete.');
  }

  Future<void> seedMissingSongs(
      {Duration delayBetweenAdds = const Duration(milliseconds: 200)}) async {
    debugPrint('[Seeder] Checking permissions for audio query');
    try {
      final permission = await audioQuery.permissionsStatus();
      debugPrint('[Seeder] Permission status: $permission');
      if (!permission) {
        debugPrint(
            '[Seeder] Permission to query audio not granted. Skipping seeding.');
        return;
      }
    } catch (e) {
      debugPrint('[Seeder] Unable to check audio permission: $e');
      return;
    }

    debugPrint('[Seeder] Querying all songs...');
    final List<SongModel> allSongs = await audioQuery.querySongs();
    debugPrint('[Seeder] Found ${allSongs.length} songs');

    final List<String> validFilePaths = [];

    for (final song in allSongs) {
      final ext = p.extension(song.data).toLowerCase();
      if (!(song.isMusic == true && allowedExtensions.contains(ext))) {
        debugPrint('[Seeder] Skipping non-music or unsupported extension: ${song
            .data}');
        continue;
      }

      final file = File(song.data);
      if (!await file.exists()) {
        debugPrint('[Seeder] File does not exist, skipping: ${song.data}');
        continue;
      }

      try {
        final metadata = await MetadataRetriever.fromFile(file);
        debugPrint('[Seeder] Retrieved metadata for: ${song.data}');

        final hasAnyMetadata = (metadata.trackName
            ?.trim()
            .isNotEmpty ?? false) ||
            (metadata.authorName
                ?.trim()
                .isNotEmpty ?? false) ||
            (metadata.albumName
                ?.trim()
                .isNotEmpty ?? false);

        final durationOk = (metadata.trackDuration != null &&
            metadata.trackDuration! > 30 * 1000);

        debugPrint('[Seeder] Metadata check for ${song
            .data} - hasAnyMetadata: $hasAnyMetadata, durationOk: $durationOk');

        if (hasAnyMetadata && durationOk) {
          validFilePaths.add(song.data);
          debugPrint('[Seeder] Added valid song: ${song.data}');
        }
      } catch (e, st) {
        debugPrint(
            '[Seeder] Failed to read metadata for ${song.data}: $e\n$st');
      }
    }

    debugPrint(
        '[Seeder] Starting to seed ${validFilePaths.length} valid songs');
    await seedFiles(validFilePaths, delayBetweenAdds: delayBetweenAdds);
  }

  Future<void> seedFiles(List<String> filePaths,
      {Duration delayBetweenAdds = const Duration(milliseconds: 100)}) async {
    debugPrint('[Seeder] Beginning seedFiles with ${filePaths.length} files');
    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      debugPrint('[Seeder] Current torrent stats: $rawStats');

      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();

      final Set<String> activeHashes = currentTorrents
          .map((t) => t['info_hash']?.toString())
          .whereType<String>()
          .toSet();

      debugPrint('[Seeder] Active torrent hashes: $activeHashes');

      for (final path in filePaths) {
        debugPrint('[Seeder] Processing file for seeding: $path');
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('[Seeder] File missing, skipping: $path');
          continue;
        }

        final title = p.basenameWithoutExtension(path);
        final safeTitle = title.replaceAll(RegExp(r"[^\w\s]"), "_");
        final torrentFilePath = p.join(torrentsDir, '$safeTitle.torrent');
        final torrentFile = File(torrentFilePath);

        try {
          if (!await torrentFile.exists()) {
            debugPrint(
                '[Seeder] Torrent file does not exist, creating: $torrentFilePath');
            final created = await LibtorrentWrapper.createTorrent(
              path,
              torrentFilePath,
              trackers: [], // ⚠️ Optional: Remove if going trackerless
            );
            debugPrint(
                '[Seeder] Torrent creation result for $torrentFilePath: $created');
            if (!created) {
              debugPrint('[Seeder] Torrent creation failed, skipping $path');
              continue;
            }
          } else {
            debugPrint(
                '[Seeder] Torrent file already exists: $torrentFilePath');
          }

          final infoHash = await LibtorrentWrapper.getInfoHash(torrentFilePath);
          debugPrint('[Seeder] InfoHash for torrent file: $infoHash');
          if (infoHash == null || infoHash.isEmpty) {
            debugPrint('[Seeder] Invalid infoHash, skipping file: $path');
            continue;
          }

          final isKnown = knownHashes.contains(infoHash);
          final isActive = activeHashes.contains(infoHash);

          debugPrint('[Seeder] isKnown: $isKnown, isActive: $isActive');

          if (!isKnown || !isActive) {
            if (isKnown && !isActive) {
              debugPrint('[Seeder] Removing stale known hash: $infoHash');
              knownHashes.remove(infoHash);
              _hashToPathMap.remove(infoHash);
              _metadataCache.remove(infoHash);
            }

            debugPrint('[Seeder] Adding torrent to libtorrent for $path');
            final added = await LibtorrentWrapper.addTorrent(
              torrentFilePath,
              savePath: p.dirname(path),
              seedMode: true,
              announce: false,
              enableDHT: false,
              enableLSD: true,
              enableUTP: true,
              enableTrackers: false,
              enablePeerExchange: true,
            );

            debugPrint('[Seeder] Add torrent result: $added');
            if (!added) {
              debugPrint('[Seeder] Failed to add torrent for $path');
              continue;
            }

            knownHashes.add(infoHash);
            _hashToPathMap[infoHash] = path;

            await _saveKnownHashes();
            await _saveHashToPathMap();

            debugPrint('[Seeder] ✅ Seeding (P2P): $title');
            await Future.delayed(delayBetweenAdds);
          } else {
            debugPrint('[Seeder] Torrent already known and active: $title');
          }
        } catch (e) {
          debugPrint('[Seeder] ⚠️ Error processing $title\n$e');
        }
      }
    } catch (e) {
      debugPrint('[Seeder] 🚨 Torrent fetch failed: $e');
    }
  }

  Future<bool> removeTorrent(String infoHash) async {
    debugPrint('[Seeder] Attempting to remove torrent: $infoHash');
    if (!knownHashes.contains(infoHash)) {
      debugPrint('[Seeder] InfoHash not known: $infoHash');
      return false;
    }

    try {
      await LibtorrentWrapper.removeTorrentByInfoHash(infoHash);

      final torrentPath = getTorrentFilePathForHash(infoHash);
      if (torrentPath != null) {
        final torrentFile = File(torrentPath);
        if (await torrentFile.exists()) {
          await torrentFile.delete();
          debugPrint('[Seeder] Deleted torrent file at $torrentPath');
        } else {
          debugPrint('[Seeder] Torrent file not found at $torrentPath');
        }
      }

      knownHashes.remove(infoHash);
      _hashToPathMap.remove(infoHash);
      _metadataCache.remove(infoHash);

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
    debugPrint('[Seeder] Loading known hashes...');
    final file = File(hashDbPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        knownHashes
          ..clear()
          ..addAll(jsonList.whereType<String>());
        debugPrint('[Seeder] Loaded ${knownHashes.length} known hashes');
      } catch (e, st) {
        debugPrint('[Seeder] Failed to load known hashes: $e\n$st');
      }
    } else {
      debugPrint('[Seeder] Known hashes file does not exist');
    }
  }

  Future<void> _loadHashToPathMap() async {
    debugPrint('[Seeder] Loading hash-to-path map...');
    final file = File(hashToPathMapPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _hashToPathMap.clear();
        _hashToPathMap.addAll(Map<String, String>.from(jsonDecode(content)));
        debugPrint('[Seeder] Loaded hash-to-path map with ${_hashToPathMap
            .length} entries');
      } catch (e, st) {
        debugPrint('[Seeder] Failed to load hash-to-path map: $e\n$st');
      }
    } else {
      debugPrint('[Seeder] Hash-to-path map file does not exist');
    }
  }

  Future<void> _saveKnownHashes() async {
    debugPrint('[Seeder] Saving known hashes...');
    final file = File(hashDbPath);
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
      debugPrint('[Seeder] Created directory for known hashes file');
    }
    final tempFile = File('$hashDbPath.tmp');
    await tempFile.writeAsString(jsonEncode(knownHashes.toList()));
    debugPrint('[Seeder] Written temp known hashes file');
    await tempFile.rename(hashDbPath);
    debugPrint('[Seeder] Renamed temp known hashes file to $hashDbPath');
  }

  Future<void> _saveHashToPathMap() async {
    debugPrint('[Seeder] Saving hash-to-path map...');
    final file = File(hashToPathMapPath);
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
      debugPrint('[Seeder] Created directory for hash-to-path map file');
    }
    final tempFile = File('$hashToPathMapPath.tmp');
    await tempFile.writeAsString(jsonEncode(_hashToPathMap));
    debugPrint('[Seeder] Written temp hash-to-path map file');
    await tempFile.rename(hashToPathMapPath);
    debugPrint(
        '[Seeder] Renamed temp hash-to-path map file to $hashToPathMapPath');
  }

  String? getTorrentFilePathForHash(String infoHash) {
    if (!knownHashes.contains(infoHash)) {
      debugPrint(
          '[Seeder] getTorrentFilePathForHash: infoHash not known: $infoHash');
      return null;
    }
    final title = p.basenameWithoutExtension(
        _hashToPathMap[infoHash] ?? infoHash);
    final safeTitle = title.replaceAll(RegExp(r"[^\w\s]"), "_");
    final path = p.join(torrentsDir, '$safeTitle.torrent');
    debugPrint(
        '[Seeder] getTorrentFilePathForHash: path for $infoHash is $path');
    return path;
  }

  /// Returns cached metadata if available, otherwise loads from file and caches it.
  Future<Map<String, dynamic>?> getMetadataForHash(String infoHash) async {
    if (_metadataCache.containsKey(infoHash)) {
      debugPrint('[Seeder] Returning cached metadata for $infoHash');
      return _metadataCache[infoHash];
    }
    final path = _hashToPathMap[infoHash];
    if (path == null) {
      debugPrint('[Seeder] getMetadataForHash: no path for hash: $infoHash');
      return null;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[Seeder] getMetadataForHash: file not found at $path');
        return null;
      }

      final metadata = await MetadataRetriever.fromFile(file);
      final metaMap = {
        'title': metadata.trackName ?? '',
        'artist': metadata.authorName ?? '',
        'album': metadata.albumName ?? '',
        'albumArt': metadata.albumArt,
        'duration': metadata.trackDuration ?? 0,
      };
      _metadataCache[infoHash] = metaMap;
      return metaMap;
    } catch (e) {
      debugPrint('[Seeder] Failed to retrieve metadata for hash $infoHash: $e');
      return null;
    }
  }
}
