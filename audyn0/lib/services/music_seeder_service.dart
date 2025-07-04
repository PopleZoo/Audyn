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
  final Map<String, Map<String, dynamic>?> _metadataCache = {};

  Map<String, String> get hashToPathMap => _hashToPathMap;

  MusicSeederService([OnAudioQuery? audioQuery])
      : audioQuery = audioQuery ?? OnAudioQuery() {
    debugPrint('[MusicSeederService] Constructor called');
  }

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
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  Future<void> resetSeedingState() async {
    try {
      final hashFile = File(hashDbPath);
      final mapFile = File(hashToPathMapPath);
      if (await hashFile.exists()) await hashFile.delete();
      if (await mapFile.exists()) await mapFile.delete();
      knownHashes.clear();
      _hashToPathMap.clear();
      _metadataCache.clear();
    } catch (e) {
      debugPrint('[Seeder] ⚠️ Failed to reset seeding state: $e');
    }
  }

  Future<void> restartSeeding() async {
    await init();
    await resetSeedingState();

    try {
      final rawStats = await LibtorrentWrapper.getTorrentStats();
      final List<Map<String, dynamic>> currentTorrents =
      (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();

      for (final torrent in currentTorrents) {
        final infoHash = torrent['info_hash']?.toString();
        if (infoHash == null || infoHash.isEmpty) continue;
        await LibtorrentWrapper.removeTorrentByInfoHash(infoHash);
      }
    } catch (_) {}

    knownHashes.clear();
    _hashToPathMap.clear();
    _metadataCache.clear();
    await _saveKnownHashes();
    await _saveHashToPathMap();
    await seedMissingSongs();
  }

  Future<void> seedMissingSongs({Duration delayBetweenAdds = const Duration(milliseconds: 200)}) async {
    try {
      final permission = await audioQuery.permissionsStatus();
      if (!permission) return;
    } catch (_) {
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
        if (hasAnyMetadata && durationOk) validFilePaths.add(song.data);
      } catch (_) {}
    }

    await seedFiles(validFilePaths, delayBetweenAdds: delayBetweenAdds);
  }

  Future<void> seedFiles(List<String> filePaths, {Duration delayBetweenAdds = const Duration(milliseconds: 100)}) async {
    final rawStats = await LibtorrentWrapper.getTorrentStats();
    final List<Map<String, dynamic>> currentTorrents =
    (jsonDecode(rawStats) as List).whereType<Map<String, dynamic>>().toList();

    final Set<String> activeHashes = currentTorrents
        .map((t) => t['info_hash']?.toString())
        .whereType<String>()
        .toSet();

    final libtorrent = LibtorrentService();

    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) continue;

      final title = p.basenameWithoutExtension(path).replaceAll(RegExp(r"[^\w\s]"), "_");
      final torrentFilePath = p.join(torrentsDir, '$title.torrent');
      final torrentFile = File(torrentFilePath);

      String? infoHash;

      if (!await torrentFile.exists()) {
        infoHash = await libtorrent.createTorrentAndGetHash(path); // use _createTorrentAndGetHash
        if (infoHash == null) continue;
      } else {
        infoHash = await LibtorrentWrapper.getInfoHash(torrentFilePath);
        if (infoHash == null || infoHash.isEmpty) continue;
      }

      if (!activeHashes.contains(infoHash)) {
        await libtorrent.addTorrent(
          torrentFilePath,
          p.dirname(path),
          seedMode: true,
          announce: false,
          enableDHT: true,
          enableLSD: true,
          enableUTP: true,
          enableTrackers: false,
          enablePeerExchange: true,
        );
      }

      await libtorrent.putEncryptedSwarmData(infoHash, {
        'infoHash': infoHash,
        'name': title,
        'ts': DateTime.now().toIso8601String(),
      });

      if (!knownHashes.contains(infoHash)) {
        knownHashes.add(infoHash);
        _hashToPathMap[infoHash] = path;
        await _saveKnownHashes();
        await _saveHashToPathMap();
      }

      await Future.delayed(delayBetweenAdds);
    }
  }

  Future<void> _loadKnownHashes() async {
    final file = File(hashDbPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        knownHashes..clear()..addAll((jsonDecode(content) as List).cast<String>());
      } catch (_) {}
    }
  }

  Future<void> _loadHashToPathMap() async {
    final file = File(hashToPathMapPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _hashToPathMap.clear();
        _hashToPathMap.addAll(Map<String, String>.from(jsonDecode(content)));
      } catch (_) {}
    }
  }

  Future<void> _saveKnownHashes() async {
    final file = File(hashDbPath);
    final tempFile = File('$hashDbPath.tmp');
    await tempFile.writeAsString(jsonEncode(knownHashes.toList()));
    await tempFile.rename(hashDbPath);
  }

  Future<void> _saveHashToPathMap() async {
    final file = File(hashToPathMapPath);
    final tempFile = File('$hashToPathMapPath.tmp');
    await tempFile.writeAsString(jsonEncode(_hashToPathMap));
    await tempFile.rename(hashToPathMapPath);
  }

  Future<Map<String, dynamic>?> getMetadataForHash(String infoHash) async {
    if (_metadataCache.containsKey(infoHash)) return _metadataCache[infoHash];
    final path = _hashToPathMap[infoHash];
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
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
  }

  String? getTorrentFilePathForHash(String infoHash) {
    if (!knownHashes.contains(infoHash)) return null;
    final title = p.basenameWithoutExtension(_hashToPathMap[infoHash] ?? infoHash).replaceAll(RegExp(r"[^\w\s]"), "_");
    return p.join(torrentsDir, '$title.torrent');
  }

  Future<void> addTorrentByHash(String infoHash) async {
    final libtorrent = LibtorrentService();
    final path = _hashToPathMap[infoHash];
    if (path == null || path.isEmpty) return;

    final torrentPath = getTorrentFilePathForHash(infoHash);
    if (torrentPath == null || !File(torrentPath).existsSync()) return;

    await libtorrent.addTorrent(
      torrentPath,
      p.dirname(path),
      seedMode: true,
      announce: false,
      enableDHT: true,
      enableLSD: true,
      enableUTP: true,
      enableTrackers: false,
      enablePeerExchange: true,
    );
  }
}
