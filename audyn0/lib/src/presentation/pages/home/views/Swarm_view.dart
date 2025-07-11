import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'; // consolidateHttpClientResponseBytes
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../../data/services/LibtorrentService.dart';
import '../../../widgets/torrent_list_tile.dart';

class SwarmView extends StatefulWidget {
  const SwarmView({super.key});

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  final _libtorrent = LibtorrentService();
  final _audioQuery = OnAudioQuery();
  MusicSeederService? _seeder;

  final List<Map<String, dynamic>> _torrents = [];
  final List<Map<String, dynamic>> _filtered = [];
  final Map<String, Map<String, dynamic>> _metaCache = {};
  final Set<String> _localUploadHistory = {};
  final Map<String, List<String>> _vaultByHash = {};
  final Map<String, List<String>> _vaultByName = {};
  List<SongModel> _deviceSongs = [];
  final Map<String, Metadata> _validatedMetadataCache = {};

  String _search = '';
  bool _isLoading = true;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _seeder = await MusicSeederService.create();
      await _loadLocalUploadHistory();
      await _queryDeviceSongs();
      await _syncLocal();
      await _refresh();
    } catch (e, st) {
      debugPrint('[SwarmView] Bootstrap error: $e\n$st');
    }
  }

  Future<void> _queryDeviceSongs() async {
    bool granted = await _audioQuery.permissionsStatus();
    if (!granted) granted = await _audioQuery.permissionsRequest();
    if (!granted) return;

    final songs = await _audioQuery.querySongs();
    const batchSize = 5;
    final validated = <SongModel>[];

    for (var i = 0; i < songs.length; i += batchSize) {
      final batch = songs.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((song) async {
        final meta = await _extractValidMetadata(song.data);
        if (meta != null) {
          final norm = MusicSeederService.norm(p.basenameWithoutExtension(song.data));
          _validatedMetadataCache[norm] = meta;
          return song;
        }
        return null;
      }));

      validated.addAll(results.whereType<SongModel>());
    }

    if (mounted) setState(() => _deviceSongs = validated);
  }

  Future<Metadata?> _extractValidMetadata(String path) async {
    try {
      final meta = await MetadataRetriever.fromFile(File(path));
      final hasBasicInfo = (meta.trackName?.isNotEmpty ?? false) &&
          (meta.trackArtistNames?.isNotEmpty ?? false) &&
          (meta.albumArt?.isNotEmpty ?? false);

      return hasBasicInfo ? meta : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncLocal() async {
    await _indexVault();

    for (final entry in _vaultByName.entries) {
      final name = entry.key;
      final filePaths = entry.value;

      for (final filePath in filePaths) {
        final infoHash = await _getInfoHashFromLocalPath(filePath);
        if (infoHash != null && infoHash.isNotEmpty) {
          if (!await _libtorrent.isTorrentActive(infoHash)) {
            final encBytes = await File(filePath).readAsBytes();
            final plain = CryptoHelper.decryptBytes(encBytes);

            if (plain != null && plain.isNotEmpty) {
              await _saveDecryptedTorrentForDebug(filePath, plain);
              final isValid = await _isValidTorrentBytes(plain);
              if (!isValid) {
                debugPrint('[SwarmView] Invalid torrent bytes for $filePath, skipping');
                continue;
              }

              try {
                await _libtorrent.addTorrentFromBytes(
                  plain,
                  p.dirname(filePath),
                  seedMode: true,
                );
                debugPrint('[SwarmView] Added torrent from $filePath');
              } catch (e, st) {
                debugPrint('[SwarmView] Failed to add torrent from $filePath: $e\n$st');
              }
            } else {
              debugPrint('[SwarmView] Decrypted bytes empty/null for $filePath');
            }
          }
        } else {
          debugPrint('[SwarmView] InfoHash null/empty for $filePath');
        }
      }
    }

    final localTorrents = <Map<String, dynamic>>[];

    for (final hash in _vaultByHash.keys) {
      final paths = _vaultByHash[hash]!;
      final filename = p.basenameWithoutExtension(paths.first.replaceAll('.audyn', ''));
      localTorrents.add({
        'name': filename,
        'info_hash': hash,
        'vault_files': paths,
        'seed_mode': true,
      });
    }

    final enrichedList = await Future.wait(localTorrents.map(_enrichTorrent));
    final enriched = enrichedList.whereType<Map<String, dynamic>>().toList();

    if (mounted) {
      setState(() {
        _torrents.addAll(enriched);
        _applySearch();
      });
    }

    _applySearch();
  }

  Future<void> _saveDecryptedTorrentForDebug(String originalPath, Uint8List bytes) async {
    try {
      final dir = Directory(p.dirname(originalPath));
      final debugFile = File(p.join(dir.path, p.basenameWithoutExtension(originalPath) + '_decrypted_debug.torrent'));
      await debugFile.writeAsBytes(bytes);
      debugPrint('[SwarmView] Saved decrypted debug torrent at ${debugFile.path}');
    } catch (e, st) {
      debugPrint('[SwarmView] Failed to save decrypted debug torrent: $e\n$st');
    }
  }

  Future<bool> _isValidTorrentBytes(Uint8List bytes) async {
    try {
      final hash = await _libtorrent.getInfoHashFromDecryptedBytes(bytes);
      return hash != null && hash.isNotEmpty;
    } catch (e, st) {
      debugPrint('[SwarmView] Torrent validation failed: $e\n$st');
      return false;
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _isError = false;
      _torrents.clear();
      _filtered.clear();
      _metaCache.clear();
    });

    try {
      await _seeder?.seedMissingSongs();
      await _indexVault();

      final supabaseTorrents = await _fetchTorrentsFromSupabase();
      final enrichedList = await Future.wait(
        supabaseTorrents.map(_enrichTorrent),
      );
      final enriched = enrichedList.whereType<Map<String, dynamic>>().toList();

      if (mounted) {
        setState(() {
          _torrents.addAll(enriched);
          _applySearch();
        });
      }
    } catch (e, st) {
      debugPrint('[SwarmView] refresh error: $e\n$st');
      if (mounted) setState(() => _isError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _indexVault() async {
    _vaultByHash.clear();
    _vaultByName.clear();

    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'torrents'));
    if (!await dir.exists()) return;

    await for (final file in dir.list(recursive: true)) {
      if (file is! File || !file.path.endsWith('.audyn.torrent')) continue;

      final encBytes = await file.readAsBytes();
      final plain = CryptoHelper.decryptBytes(encBytes);
      if (plain == null || plain.isEmpty) {
        continue;
      }

      final hash = await _libtorrent.getInfoHashFromDecryptedBytes(plain);
      if (hash == null || hash.isEmpty) {
        continue;
      }

      final filename = p.basenameWithoutExtension(file.path.replaceAll('.audyn', ''));
      final name = MusicSeederService.norm(filename);

      _vaultByHash.putIfAbsent(hash, () => []).add(file.path);
      _vaultByName.putIfAbsent(name, () => []).add(file.path);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTorrentsFromSupabase() async {
    try {
      final List<dynamic> data = await Supabase.instance.client
          .from('torrents')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[SwarmView] Failed to fetch torrents from Supabase: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _enrichTorrent(Map<String, dynamic> t) async {
    final name = t['name']?.toString() ?? '';
    final infoHash = t['info_hash']?.toString();
    if (name.isEmpty || infoHash == null) return null;

    final norm = MusicSeederService.norm(name);
    if (_metaCache.containsKey(norm)) return {...t, ..._metaCache[norm]!};

    Map<String, dynamic>? metadata;

    try {
      metadata = await Supabase.instance.client
          .from('torrent_metadata')
          .select()
          .eq('info_hash', infoHash)
          .maybeSingle();
    } catch (_) {}

    metadata ??= await _seeder?.getMetadataForName(name);

    final cached = <String, dynamic>{
      'title': metadata?['title'] ?? name,
      'artist': metadata?['artist'] ?? 'Unknown',
      'artistnames': metadata?['artistnames'] ?? [],
      'album': metadata?['album'] ?? 'Unknown',
      'albumArtUrl': metadata?['album_art_url'],
      'art': null,
    };

    if (cached['albumArtUrl'] != null) {
      try {
        final uri = Uri.tryParse(cached['albumArtUrl']);
        if (uri != null) {
          final req = await HttpClient().getUrl(uri);
          final res = await req.close();
          if (res.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(res);
            cached['art'] = bytes;
          }
        }
      } catch (_) {}
    }

    _metaCache[norm] = cached;

    return {...t, ...cached};
  }

  Future<String?> _getInfoHashFromLocalPath(String path) async {
    try {
      final encBytes = await File(path).readAsBytes();
      final plain = CryptoHelper.decryptBytes(encBytes);
      if (plain == null) return null;
      return await _libtorrent.getInfoHashFromDecryptedBytes(plain);
    } catch (_) {
      return null;
    }
  }

  void _applySearch() {
    final q = _search.toLowerCase();
    _filtered
      ..clear()
      ..addAll(_torrents.where((t) {
        return [t['name'], t['title'], t['artist'], t['album']]
            .any((field) => (field?.toString().toLowerCase() ?? '').contains(q));
      }));
    if (mounted) setState(() {});
  }

  Widget _buildTorrentTile(Map<String, dynamic> t, ThemeData theme) {
    return TorrentListTile(
      torrent: t,
      onTap: () => _showTorrentDialog(t, theme),
    );
  }

  void _showTorrentDialog(Map<String, dynamic> t, ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t['title'] ?? t['name'] ?? 'Unknown'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t['art'] != null) Image.memory(t['art'], height: 100),
            Text('Artist: ${t['artist'] ?? 'Unknown'}'),
            Text('Album: ${t['album'] ?? 'Unknown'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLocalUploadHistory() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final file = File(p.join(base.path, 'upload_history.json'));

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(contents);
        _localUploadHistory
          ..clear()
          ..addAll(jsonData.whereType<String>());
        debugPrint('[SwarmView] Loaded upload history: ${_localUploadHistory.length} entries.');
      } else {
        _localUploadHistory.clear();
        debugPrint('[SwarmView] No upload history file, starting fresh.');
      }
    } catch (e, st) {
      debugPrint('[SwarmView] Loading upload history failed: $e\n$st');
      _localUploadHistory.clear();
    }
  }

  /// Call this after creating/adding a local encrypted torrent file
  /// to upload its info to Supabase and update local upload history.
  Future<void> addLocalEncrypted(Map<String, dynamic> t) async {
    final encPath = (t['vault_files'] as List?)?.first;
    if (encPath == null) return;

    try {
      final bytes = await File(encPath).readAsBytes();
      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain == null || plain.isEmpty) throw 'Decrypt failed';

      final infoHash = await _libtorrent.getInfoHashFromDecryptedBytes(plain);
      if (infoHash == null) throw 'Invalid infoHash';

      final alreadyAdded = await _libtorrent.isTorrentActive(infoHash);
      if (!alreadyAdded) {
        final dir = await getApplicationDocumentsDirectory();
        final ok = await _libtorrent.addTorrentFromBytes(
          plain,
          dir.path,
          seedMode: true,
        );
        if (!ok) throw 'Add to session failed';
      }

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Not signed in';

      final rows = await Supabase.instance.client
          .from('torrents')
          .select()
          .eq('info_hash', infoHash)
          .limit(1);
      final exists = rows != null && rows.isNotEmpty;

      if (!exists) {
        final enriched = await _enrichTorrent(t);

        await Supabase.instance.client.from('torrents').insert({
          'info_hash': infoHash,
          'name': enriched?['title'] ?? t['name'] ?? 'Unknown',
          'owner_id': user.id,
        });

        await Supabase.instance.client.from('torrent_metadata').insert({
          'info_hash': infoHash,
          'title': enriched?['title'] ?? 'Unknown',
          'artist': enriched?['artist'] ?? 'Unknown Artist',
          'album': enriched?['album'],
          'album_art_url': enriched?['albumArtUrl'],
        });
      }

      if (_localUploadHistory.add(infoHash)) {
        final base = await getApplicationDocumentsDirectory();
        final file = File(p.join(base.path, 'upload_history.json'));
        await file.writeAsString(jsonEncode(_localUploadHistory.toList()));
      }

      debugPrint('[SwarmView] Uploaded torrent infoHash: $infoHash');
      if (mounted) setState(() {
        if (!_torrents.any((t) => t['info_hash'] == infoHash)) {
          _torrents.add(t);
          _applySearch();
        }
      });
    } catch (e, st) {
      debugPrint('[SwarmView] Failed to add local encrypted torrent: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding torrent: $e')),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh torrents',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search torrents...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                _search = val;
                _applySearch();
              },
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
          ? Center(
        child: Text(
          'Error loading torrents\nPlease try again later.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      )
          : _filtered.isEmpty
          ? Center(
        child: Text(
          'No torrents found.',
          style: theme.textTheme.bodyMedium,
        ),
      )
          : ListView.builder(
        itemCount: _filtered.length,
        itemBuilder: (_, index) => _buildTorrentTile(_filtered[index], theme),
      ),
    );
  }
}