/*─────────────────────────────────────────────────────────────*\
│  lib/services/music_seeder_service.dart                      │
\*─────────────────────────────────────────────────────────────*/

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/CryptoHelper.dart';
import '../src/data/services/LibtorrentService.dart';

class MusicSeederService {
  MusicSeederService([OnAudioQuery? aq]) : audioQuery = aq ?? OnAudioQuery();

  /*─────────────────────────  DI  ───────────────────────────*/

  final OnAudioQuery       audioQuery;
  final LibtorrentService  _libtorrent = LibtorrentService();

  /*─────────────────────────  STATE  ─────────────────────────*/

  late final String torrentsDir;                       // <app>/torrents
  final Set<String> knownTorrentNames      = {};       // normalised names
  final Map<String, String> _nameToPathMap = {};       // name → song file
  final Map<String, Map<String, dynamic>> _metaCache = {};

  Map<String,String> get nameToPathMap => _nameToPathMap;

  static const _allowedExt = ['.mp3', '.flac', '.wav', '.m4a'];

  /*─────────────────────────  INIT  ─────────────────────────*/

  Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    torrentsDir = p.join(base.path, 'torrents');        // encrypted files live here
    await Directory(torrentsDir).create(recursive: true);
  }

  /*─────────────────────────  NORMALISER  ───────────────────*/

  static String _norm(String name) =>
      p.basenameWithoutExtension(name).toLowerCase().replaceAll(RegExp(r'[^\w]+'), '_');

  /*─────────────────────────  PUBLIC          ───────────────*/

  Future<void> seedMissingSongs({Duration gap = const Duration(milliseconds: 120)}) async {
    if (!(await audioQuery.permissionsStatus())) {
      if (!await audioQuery.permissionsRequest()) return;
    }

    final songs = await audioQuery.querySongs();
    final valid = <String>[];

    for (final s in songs) {
      final ext = p.extension(s.data).toLowerCase();
      if (!_allowedExt.contains(ext)) continue;

      final f = File(s.data);
      if (!await f.exists()) continue;

      try {
        final meta = await MetadataRetriever.fromFile(f);
        final okDuration = (meta.trackDuration ?? 0) > 30 * 1000;
        final okInfo     = (meta.trackName ?? '').trim().isNotEmpty;
        if (okDuration && okInfo) valid.add(s.data);
      } catch (_) {/* ignore */}
    }

    await _seedFiles(valid, gap);
  }

  /*─────────────────────────  CORE SEED LOOP  ───────────────*/

  Future<void> _seedFiles(List<String> paths, Duration gap) async {
    // fetch current torrent list once
    final Set<String> active = {
      ...(await _libtorrent.getAllTorrents())
          .map((m) => _norm(m['name']?.toString() ?? ''))
    };

    for (final songPath in paths) {
      final songFile = File(songPath);
      if (!await songFile.exists()) continue;

      final normName   = _norm(songPath);
      final encPath    = p.join(torrentsDir, '$normName.audyn.torrent');

      Uint8List torrentBytesPlain;

      /*------------------------- create ----------------------*/
      try {
        torrentBytesPlain =
            await _libtorrent.createTorrentBytes(songFile.path) ?? Uint8List(0);
        if (torrentBytesPlain.isEmpty) {
          debugPrint('[Seeder] ❌ Failed to create torrent for $songPath');
          continue;
        }
      } catch (e) {
        debugPrint('[Seeder] ❌ Native createTorrentBytes failed: $e');
        continue;
      }

      /*------------------------- store encrypted ------------*/
      try {
        final encBytes = CryptoHelper.encryptBytes(torrentBytesPlain);
        await File(encPath).writeAsBytes(encBytes, flush: true);
      } catch (e) {
        debugPrint('[Seeder] ❌ Writing encrypted file failed: $e');
        continue;
      }

      /*------------------------- add to session -------------*/
      if (!active.contains(normName)) {
        final ok = await _libtorrent.addTorrentFromBytes(
          torrentBytesPlain,
          p.dirname(songPath),
          seedMode: true,
          announce : false,
        );
        if (!ok) {
          debugPrint('[Seeder] ⚠️ addTorrentFromBytes failed for $songPath');
          continue;
        }
      }

      /*------------------------- bookkeeping ----------------*/
      if (knownTorrentNames.add(normName)) {
        _nameToPathMap[normName] = songPath;
      }

      await Future.delayed(gap);
    }
  }

  /*─────────────────────────  METADATA CACHE  ───────────────*/

  Future<Map<String,dynamic>?> getMetadataForName(String anyName) async {
    final key = _norm(anyName);
    if (_metaCache.containsKey(key)) return _metaCache[key];

    final path = _nameToPathMap[key];
    if (path == null) return null;

    try {
      final meta = await MetadataRetriever.fromFile(File(path));
      return _metaCache[key] = {
        'title'    : meta.trackName  ?? '',
        'artist'   : meta.authorName ?? '',
        'album'    : meta.albumName  ?? '',
        'albumArt' : meta.albumArt,
        'duration' : meta.trackDuration ?? 0,
      };
    } catch (e) {
      debugPrint('[Meta] read error: $e');
      return null;
    }
  }

  /*─────────────────────────  UTILS  ────────────────────────*/

  String? getEncryptedTorrentPath(String anyName) {
    final key = _norm(anyName);
    if (!knownTorrentNames.contains(key)) return null;
    return p.join(torrentsDir, '$key.audyn.torrent');
  }

  List<String> getLocalFilesForTorrent(String anyName) {
    final path = _nameToPathMap[_norm(anyName)];
    if (path == null) return [];
    final f = File(path);
    if (f.existsSync()) return [p.basename(path)];
    final d = Directory(path);
    if (!d.existsSync()) return [];
    return d
        .listSync()
        .whereType<File>()
        .map((e) => p.basename(e.path))
        .toList();
  }
}
