// Full Fat SwarmView.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../../data/services/LibtorrentService.dart';

class SwarmView extends StatefulWidget {
  const SwarmView({super.key});

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  final _libtorrent = LibtorrentService();
  final _audioQuery = OnAudioQuery();
  MusicSeederService? _seeder;

  final _torrents = <Map<String, dynamic>>[];
  final _filtered = <Map<String, dynamic>>[];
  final _metaCache = <String, Map<String, dynamic>>{};
  final _localUploadHistory = <String>{};
  final _vaultByHash = <String, List<String>>{};
  final _vaultByName = <String, List<String>>{};
  List<SongModel> _deviceSongs = [];

  var _search = '';
  var _isLoading = true;
  var _isError = false;

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
      final results = await Future.wait(batch.map((song) {
        return _hasValidSongMetadata(song.data);
      }));

      for (var j = 0; j < results.length; j++) {
        if (results[j]) validated.add(batch.elementAt(j));
      }
    }

    setState(() => _deviceSongs = validated);
  }

  Future<bool> _hasValidSongMetadata(String path) async {
    try {
      final meta = await MetadataRetriever.fromFile(File(path));
      return (meta.trackName?.isNotEmpty ?? false) &&
          (meta.trackArtistNames?.isNotEmpty ?? false) &&
          (meta.albumArt?.isNotEmpty ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncLocal() async {
    final seeded = await _seeder?.seedMissingSongs() ?? [];
    if (seeded.isEmpty) return;

    await _indexVault();

    for (final path in seeded) {
      final name = p.basenameWithoutExtension(path.replaceAll('.audyn.torrent', ''));
      await _addLocalEncrypted({'name': name, 'vault_files': [path]});
      final infoHash = await _getInfoHashFromLocalPath(path);
      if (infoHash == null || infoHash.isEmpty) {
        debugPrint('[SwarmView] Skipping invalid infoHash for $path');
        continue;
      }

      debugPrint('[SwarmView] Starting torrent by hash: $infoHash');
      await _libtorrent.startTorrentByHash(infoHash);


    }

    for (var i = 0; i < _torrents.length; i++) {
      final enriched = await _enrichTorrent(_torrents[i]);
      if (enriched != null) _torrents[i] = enriched;
    }

    _applySearch();
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
      // Recheck and reindex everything
      await _queryDeviceSongs(); // ← revalidates local audio files
      await _seeder?.seedMissingSongs(); // ← creates new torrents if missing
      await _indexVault(); // ← ensures local vault is in sync

      // Upload new torrents + start seeding
      for (final entry in _vaultByName.entries) {
        await _addLocalEncrypted({
          'name': entry.key,
          'vault_files': entry.value,
        });
      }

      // Fetch + enrich torrents
      final supabaseTorrents = await _fetchTorrentsFromSupabase();
      final enriched = await Future.wait(supabaseTorrents.map(_enrichTorrent));
      _torrents.addAll(enriched.whereType<Map<String, dynamic>>());

      _applySearch();
    } catch (e, st) {
      debugPrint('[SwarmView] Full refresh error: $e\n$st');
      setState(() => _isError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _indexVault() async {
    _vaultByHash.clear();
    _vaultByName.clear();
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'vault'));
    if (!await dir.exists()) return;

    await for (final f in dir.list(recursive: true)) {
      if (f is! File || !f.path.endsWith('.audyn.torrent')) continue;
      final plain = CryptoHelper.decryptBytes(await f.readAsBytes());
      if (plain == null || plain.isEmpty) continue;
      final hash = await _libtorrent.getInfoHashFromDecryptedBytes(plain);
      if (hash == null) {
        debugPrint('[SwarmView] Invalid torrent hash for file: ${f.path}');
        continue; // skip this file
      }
      final name = p.basenameWithoutExtension(f.path.replaceAll('.audyn', ''));
      if (hash != null) _vaultByHash.putIfAbsent(hash, () => []).add(f.path);
      _vaultByName.putIfAbsent(MusicSeederService.norm(name), () => []).add(f.path);
    }
  }

  Future<Map<String, dynamic>?> _enrichTorrent(Map<String, dynamic> t) async {
    final name = t['name'] ?? '';
    final infoHash = t['info_hash'];
    if (name.isEmpty || infoHash == null) return null;

    final norm = MusicSeederService.norm(name.toString());
    if (_metaCache.containsKey(norm)) return {...t, ..._metaCache[norm]!};

    try {
      final meta = await _seeder?.getMetadataForName(name);
      final cached = {
        'title': meta?['title'] ?? name,
        'artist': meta?['artist'] ?? 'Unknown',
        'artistnames': meta?['artistnames'] ?? [],
        'album': meta?['album'] ?? 'Unknown',
        'albumArtUrl': meta?['album_art_url'],
        'art_url': meta?['album_art_url'],
      };
      _metaCache[norm] = cached;
      return {...t, ...cached};
    } catch (_) {
      return {
        ...t,
        'title': name,
        'artist': 'Unknown',
        'artistnames': [],
        'album': 'Unknown',
        'albumArtUrl': null,
        'art': null,
      };
    }
  }

  Future<String?> _getInfoHashFromLocalPath(String encPath) async {
    try {
      final bytes = await File(encPath).readAsBytes();
      if (bytes.isEmpty) {
        debugPrint('[SwarmView] Encrypted file is empty at $encPath');
        return null;
      }

      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain == null || plain.isEmpty) {
        debugPrint('[SwarmView] Failed to decrypt torrent: $encPath');
        return null;
      }

      final infoHash = await _libtorrent.getInfoHashFromDecryptedBytes(plain);
      if (infoHash == null || infoHash.isEmpty) {
        debugPrint('[SwarmView] Invalid infoHash extracted for file: $encPath');
        return null;
      }
      return infoHash;
    } catch (e, st) {
      debugPrint('[SwarmView] Error in _getInfoHashFromLocalPath: $e\n$st');
      return null;
    }
  }



  Future<Uint8List?> _getAlbumArtBytes(String name) async {
    try {
      final path = _seeder?.getEncryptedTorrentPath(name);
      if (path == null) return null;
      final metadata = await MetadataRetriever.fromFile(File(path));
      return metadata.albumArt;
    } catch (e) {
      debugPrint('Error getting album art bytes: $e');
      return null;
    }
  }



  Future<void> _addLocalEncrypted(Map<String, dynamic> t) async {
    try {
      final name = t['name'] as String;
      final vault = t['vault_files'] as List<String>;
      if (_localUploadHistory.contains(name)) return;
      if (vault.isEmpty) return;

      final encTorrentPath = _seeder?.getEncryptedTorrentPath(name);
      if (encTorrentPath == null) {
        debugPrint('[SwarmView] Encrypted torrent path not found for $name');
        return;
      }

      final infoHash = await _getInfoHashFromLocalPath(encTorrentPath);
      if (infoHash == null || infoHash.isEmpty) {
        debugPrint('[SwarmView] Invalid infoHash for $name: "$infoHash"');
        return;
      }

      await _libtorrent.startTorrentByHash(infoHash);

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debugPrint('[SwarmView] No signed-in user');
        return;
      }

      final meta = await _seeder?.getMetadataForName(name);
      final title = meta?['title'] ?? name;
      final artist = meta?['artist'] ?? 'Unknown';
      final album = meta?['album'] ?? 'Unknown';

      // Extract album art bytes
      final albumArtBytes = await _getAlbumArtBytes(name);
      String? albumArtUrl;

      if (albumArtBytes != null) {
        try {
          final filePath = 'album_art/$infoHash.jpg';

          final uploadResult = await Supabase.instance.client.storage
              .from('album-art-bucket')
              .uploadBinary(filePath, albumArtBytes);

          if (uploadResult != null) {
            // getPublicUrl returns a String URL directly in your version
            final String publicUrl = Supabase.instance.client.storage
                .from('album-art-bucket')
                .getPublicUrl(filePath);

            if (publicUrl.isNotEmpty) {
              albumArtUrl = publicUrl;
            } else {
              debugPrint('Error getting public URL: URL is empty');
            }
          } else {
            debugPrint('Upload returned null');
          }
        } catch (e) {
          debugPrint('Upload exception: $e');
        }
      }



      await Supabase.instance.client
          .from('torrents')
          .upsert({
        'info_hash': infoHash,
        'name': name,
        'owner_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'info_hash');

      await Supabase.instance.client
          .from('torrent_metadata')
          .upsert({
        'info_hash': infoHash,
        'title': title,
        'artist': artist,
        'album': album,
        'album_art_url': albumArtUrl,
      }, onConflict: 'info_hash');

      final ip = await _getPublicIp();
      if (ip != null) {
        final ipEnc = base64Encode(CryptoHelper.encryptBytes(utf8.encode(ip)));
        await Supabase.instance.client
            .from('seeder_peers')
            .upsert({
          'user_id': user.id,
          'info_hash': infoHash,
          'ip_enc': ipEnc,
          'last_seen': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,info_hash');
      }

      await _libtorrent.startTorrentByHash(infoHash);

      _localUploadHistory.add(name);
      await _saveLocalUploadHistory();

    } catch (e, st) {
      debugPrint('[SwarmView] _addLocalEncrypted error: $e\n$st');
    }
  }




  Future<String?> _getPublicIp() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final ip = await response.transform(utf8.decoder).join();
        return ip.trim();
      }
      return null;
    } catch (e) {
      debugPrint('[SwarmView] Failed to get public IP: $e');
      return null;
    }
  }

  Future<void> _loadLocalUploadHistory() async {
    final f = File(p.join((await getApplicationDocumentsDirectory()).path, 'uploaded_history.json'));
    if (await f.exists()) {
      final data = jsonDecode(await f.readAsString()) as List;
      _localUploadHistory.addAll(data.cast<String>());
    }
  }

  Future<void> _saveLocalUploadHistory() async {
    final f = File(p.join((await getApplicationDocumentsDirectory()).path, 'uploaded_history.json'));
    await f.writeAsString(jsonEncode(_localUploadHistory.toList()));
  }

  void _applySearch() {
    final q = _search.trim().toLowerCase();
    _filtered.clear();
    _filtered.addAll(_torrents.where((t) {
      return [
        t['name'],
        t['title'],
        t['artist'],
        t['album'],
      ].any((field) => (field?.toString().toLowerCase() ?? '').contains(q));
    }));
    setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetchTorrentsFromSupabase() async {
    try {
      final data = await Supabase.instance.client
          .from('torrents')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  Widget buildTorrentTile(Map<String, dynamic> t, ThemeData theme) {
    final isLocal = (t['vault_files'] as List?)?.isNotEmpty ?? false;
    final isSeeding = (t['state'] == 5) || (t['seed_mode'] == true);

    return ListTile(
      leading: (t['art_url'] is String && (t['art_url'] as String).isNotEmpty)
          ? Image.network(t['art_url'], width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.music_note))
          : const Icon(Icons.music_note),
      title: Text(t['title'] ?? ''),
      subtitle: Text(t['artist'] ?? 'Unknown'),
      trailing: Icon(
        isLocal
            ? Icons.check_circle
            : isSeeding
            ? Icons.cloud_upload
            : Icons.cloud_download,
        color: isLocal
            ? theme.colorScheme.secondary
            : isSeeding
            ? theme.colorScheme.primary
            : Colors.white38,
      ),
      onTap: () => showTorrentDialog(t, theme),
    );
  }

  void showTorrentDialog(Map<String, dynamic> t, ThemeData th) {
    final isSeeding = t['state'] == 5 || t['seed_mode'] == true;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t['art_url'] != null)
              Image.network(t['art_url'], width: 100, height: 100, fit: BoxFit.cover),
            Text(t['title'] ?? 'Unknown', style: th.textTheme.titleLarge),
            Text(t['artist'] ?? 'Unknown Artist'),
            ElevatedButton(
              onPressed: () async {
                final infoHash = t['info_hash'];
                if (infoHash != null) await _libtorrent.startTorrentByHash(infoHash);
                Navigator.pop(context);
              },
              child: Text(isSeeding ? 'Stop Seeding' : 'Start Seeding'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Swarm'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)
      ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
          ? const Center(child: Text('Failed to load swarm.'))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search torrents',
              ),
              onChanged: (v) {
                _search = v;
                _applySearch();
              },
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('No torrents found'))
                : ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) => buildTorrentTile(_filtered[i], theme),
            ),
          ),
          const SizedBox(height: 8),
          Text('Device Songs Validated: ${_deviceSongs.length}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
