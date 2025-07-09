import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../../data/services/LibtorrentService.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';


const bool kDebugSwarmSupabase = true; // set false in production

class SwarmView extends StatefulWidget {
  const SwarmView({super.key});
  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  /* ── services ───────────────────────────────────────────── */
  final _libtorrent = LibtorrentService();
  final _seeder     = MusicSeederService();

  /* ── state ──────────────────────────────────────────────── */
  final _metaCache = <String, Map<String, dynamic>>{};
  final _torrents  = <Map<String, dynamic>>[];
  var   _filtered  = <Map<String, dynamic>>[];

  /// local vault indexes
  var _vaultByHash = <String, List<String>>{};
  var _vaultByName = <String, List<String>>{};

  /// hashes that *this device* has previously uploaded (persisted)
  final _localUploadHistory = <String>{};

  var _isLoading = true;
  var _isError   = false;
  var _search    = '';

  /* ── lifecycle ──────────────────────────────────────────── */
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadLocalUploadHistory();
    await _refresh();
  }

  /* ── upload‑history persistence ────────────────────────── */
  Future<void> _saveLocalUploadHistory() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final file = File(p.join(base.path, 'uploaded_history.json'));
      await file.writeAsString(jsonEncode(_localUploadHistory.toList()));
    } catch (e) {
      debugPrint('[SwarmView] Failed to save upload history: $e');
    }
  }

  Future<void> _loadLocalUploadHistory() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final file = File(p.join(base.path, 'uploaded_history.json'));
      if (await file.exists()) {
        final raw = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(raw);
        _localUploadHistory.addAll(decoded.cast<String>());
      }
    } catch (e) {
      debugPrint('[SwarmView] Failed to load upload history: $e');
    }
  }

  /* ── supabase helpers ───────────────────────────────────── */
  Future<List<Map<String, dynamic>>> _fetchTorrentsFromSupabase() async {
    try {
      final data = await Supabase.instance.client.from('torrents').select();
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[SwarmView] Supabase fetch exception: $e');
      return [];
    }
  }

  /* ── background local sync ─────────────────────────────── */
  Future<void> _syncLocal() async {
    try {
      /* a) seed any missing songs → encrypted torrents on disk */
      final newlySeeded = await _seeder.seedMissingSongs();
      if (kDebugSwarmSupabase) {
        debugPrint('[SwarmView] Seeded ${newlySeeded.length} new torrents');
      }

      /* b) re‑index the vault (so “local” flags become correct) */
      await _indexVault();

      /* c) push each newly‑seeded torrent up to Supabase             *
       *    (runs serially; could be parallel if desired)             */
      for (final path in newlySeeded) {
        final name = p.basenameWithoutExtension(
            path.replaceAll('.audyn.torrent', ''));
        await _addLocalEncrypted({
          'name'        : name,
          'vault_files' : [path],
        });
      }

      /* d) re‑enrich current list with NEW vault info and refresh UI */
      for (var i = 0; i < _torrents.length; i++) {
        final updated = await _enrichTorrent(_torrents[i]);
        if (updated != null) _torrents[i] = updated;
      }
      _applySearch();       // triggers setState
    } catch (e, st) {
      debugPrint('[SwarmView] background sync error: $e\n$st');
    }
  }

  /* ── refresh (two‑phase) ───────────────────────────────── */
  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _isError = false;
      _torrents.clear();
      _filtered.clear();
      _metaCache.clear();
    });

    try {
      await _seeder.init();

      // STEP 1: Re-index vault so you know all local torrents now
      await _indexVault();

      // STEP 2: Fetch torrents from Supabase and enrich + show them immediately
      final supabaseTorrents = await _fetchTorrentsFromSupabase();
      if (kDebugSwarmSupabase) {
        debugPrint('[SwarmView] Fetched ${supabaseTorrents.length} torrents from Supabase');
      }

      // Enrich and add them to _torrents right away
      for (final raw in supabaseTorrents) {
        final enriched = await _enrichTorrent(raw);
        if (enriched != null) _torrents.add(enriched);
      }
      _applySearch();

      // STEP 3: Seed missing local songs (this generates encrypted torrents)
      final newlySeeded = await _seeder.seedMissingSongs();
      if (kDebugSwarmSupabase) {
        debugPrint('[SwarmView] Seeded ${newlySeeded.length} new torrents');
      }

      // STEP 4: Add local torrents in background, update UI as they get added
      for (final path in newlySeeded) {
        final name = p.basenameWithoutExtension(path.replaceAll('.audyn.torrent', ''));
        final localTorrentMap = {'name': name, 'vault_files': [path]};
        _addLocalEncrypted(localTorrentMap).then((_) async {
          // After adding, fetch the record from Supabase, enrich it, then update UI
          try {
            final infoHash = await _getInfoHashFromLocalPath(path);
            if (infoHash == null) return;

            final rows = await Supabase.instance.client
                .from('torrents')
                .select()
                .eq('info_hash', infoHash)
                .maybeSingle();

            if (rows != null) {
              final enriched = await _enrichTorrent(rows);
              if (enriched != null) {
                // Add only if not already present
                if (!_torrents.any((t) => t['info_hash'] == infoHash)) {
                  setState(() {
                    _torrents.add(enriched);
                    _applySearch(notify: false);
                  });
                }
              }
            }
          } catch (e, st) {
            debugPrint('[SwarmView] Error updating UI after adding local torrent: $e\n$st');
          }
        });
      }
    } catch (e, st) {
      debugPrint('[SwarmView] refresh error: $e\n$st');
      _isError = true;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Helper to get infoHash from decrypted torrent bytes of a vault path
  Future<String?> _getInfoHashFromLocalPath(String encPath) async {
    try {
      final bytes = await File(encPath).readAsBytes();
      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain == null || plain.isEmpty) return null;
      return await _libtorrent.getInfoHashFromBytes(plain);
    } catch (e) {
      debugPrint('[SwarmView] _getInfoHashFromLocalPath error: $e');
      return null;
    }
  }


  /* ── vault index ────────────────────────────────────────── */
  Future<void> _indexVault() async {
    _vaultByHash.clear();
    _vaultByName.clear();

    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory(p.join(base.path, 'vault'));
    if (!await dir.exists()) return;

    await for (final f in dir.list(recursive: true)) {
      if (f is! File || !f.path.endsWith('.audyn.torrent')) continue;
      try {
        final bytes = await f.readAsBytes();
        final plain = CryptoHelper.decryptBytes(bytes);
        if (plain == null || plain.isEmpty) continue;

        final hash = await _libtorrent.getInfoHashFromBytes(plain);
        final fileName = p.basenameWithoutExtension(
            f.path.replaceAll('.audyn', ''));

        if (hash != null) {
          _vaultByHash.putIfAbsent(hash, () => []).add(f.path);
        }
        _vaultByName
            .putIfAbsent(MusicSeederService.norm(fileName), () => [])
            .add(f.path);
      } catch (e) {
        debugPrint('[SwarmView] Vault parse failed ${f.path}: $e');
      }
    }
  }

  /* ── enrich ─────────────────────────────────────────────── */
  Future<Map<String, dynamic>?> _enrichTorrent(Map<String, dynamic> t) async {
    final rawName = t['name']?.toString() ?? '';
    if (rawName.isEmpty) return null;

    final infoHash = t['info_hash']?.toString();
    if (infoHash == null) return null;

    final norm = MusicSeederService.norm(rawName);

    // If metadata cache already has it, return cached version early
    if (_metaCache.containsKey(norm)) {
      return {
        ...t,
        ..._metaCache[norm]!,
      };
    }

    Map<String, dynamic>? metadata;

    try {
      // Try fetching metadata from Supabase torrent_metadata table
      final response = await Supabase.instance.client
          .from('torrent_metadata')
          .select()
          .eq('info_hash', infoHash)
          .maybeSingle();

      if (response != null && response is Map<String, dynamic>) {
        metadata = response;
      }
    } catch (e) {
      debugPrint('[SwarmView] Supabase metadata fetch error: $e');
    }

    // Fallback: fetch metadata from your seeder service if no DB metadata
    if (metadata == null) {
      metadata = await _seeder.getMetadataForName(rawName);
    }

    // Compose cached metadata
    final cachedMeta = <String, dynamic>{
      'title'       : (metadata?['title'] ?? rawName).toString(),
      'artist'      : (metadata?['artist'] ?? 'Unknown Artist').toString(),
      'artistnames' : (metadata?['artistnames'] ?? []),
      'album'       : (metadata?['album'] ?? 'Unknown').toString(),
      'albumArtUrl' : metadata?['album_art_url'], // URL string or null
      'art'         : null,  // We'll fill this below if we load raw art bytes
    };

    // Cache it immediately
    _metaCache[norm] = cachedMeta;

    // If albumArtUrl is set, try to fetch image bytes from the URL
    if (cachedMeta['albumArtUrl'] != null) {
      try {
        final uri = Uri.tryParse(cachedMeta['albumArtUrl']);
        if (uri != null) {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(uri);
          final response = await request.close();
          if (response.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(response);
            cachedMeta['art'] = bytes;
          }
        }
      } catch (e) {
        debugPrint('[SwarmView] Failed to fetch album art from URL: $e');
      }
    }

    // If still no art bytes, try local file fallback
    if (cachedMeta['art'] == null) {
      final baseDir = t['save_path']?.toString() ?? '';
      final candidate = File(p.join(baseDir, rawName));
      if (await candidate.exists()) {
        try {
          final meta = await MetadataRetriever.fromFile(candidate);
          if (meta.albumArt != null) {
            cachedMeta['art'] = meta.albumArt;
          }
        } catch (_) {
          // ignore errors
        }
      }
    }

    // Return enriched torrent map
    return {
      ...t,
      ...cachedMeta,
    };
  }



  /* ── list filtering ────────────────────────────────────── */
  void _applySearch({bool notify = true}) {
    final q = _search.trim().toLowerCase();
    _filtered = _torrents.where((t) {
      return [
        t['name'],
        t['title'],
        t['artist'],
        t['album'],
      ].any((field) => (field?.toString().toLowerCase() ?? '').contains(q));
    }).toList();

    if (notify && mounted) setState(() {});
  }


  /* ── tile builder ──────────────────────────────────────── */
  Widget buildTorrentTile(Map<String,dynamic> t, ThemeData th) {
    final isLocal   = (t['vault_files'] as List?)?.isNotEmpty ?? false;
    final isSeeding = (t['seed_mode'] == true) || (t['state'] == 5);

    return ListTile(
      leading: t['art'] != null
          ? Image.memory(t['art'], width: 50, height: 50, fit: BoxFit.cover)
          : const Icon(Icons.music_note, size: 32, color: Colors.white38),
      title : Text(t['title'] ?? '',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          (t['artistnames'] as List?)?.join(', ') ??
              t['artist'] ?? 'Unknown',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(
          isLocal ? Icons.check_circle
              : isSeeding ? Icons.cloud_upload
              : Icons.cloud_download,
          color: isLocal ? th.colorScheme.secondary
              : isSeeding ? th.colorScheme.primary
              : Colors.white38),
      onTap: () => showTorrentDialog(t, th),
    );
  }

  /* ── dialog ────────────────────────────────────────────── */
  void showTorrentDialog(Map<String, dynamic> t, ThemeData th) {
    final vaultFiles = (t['vault_files'] as List<String>?) ?? [];
    final artBytes   = t['art'];

    final isSeeding = t['state'] == 5 || t['seed_mode'] == true;
    final isLocal   = isSeeding || vaultFiles.isNotEmpty;
    final savePath  = t['save_path']?.toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.all(16),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (artBytes is Uint8List)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(artBytes, width: 120, height: 120, fit: BoxFit.cover),
                )
              else
                const Icon(Icons.music_note, size: 100, color: Colors.white38),
              const SizedBox(height: 12),
              Text(
                t['title'] ?? 'Unknown',
                style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Artist: ${(t['artistnames'] as List?)?.join(', ') ?? t['artist'] ?? 'Unknown'}',
                textAlign: TextAlign.center,
              ),
              if ((t['album']?.toString().isNotEmpty ?? false))
                Text('Album: ${t['album']}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Chip(
                label: Text(isLocal ? 'Stored locally' : 'Remote only'),
                backgroundColor: isLocal
                    ? th.colorScheme.secondary.withOpacity(.2)
                    : Colors.grey.shade800,
              ),
              if (isLocal) ...[
                const SizedBox(height: 10),
                Text(
                  'Storage location${vaultFiles.length > 1 || savePath != null ? 's' : ''}:',
                  style: th.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (final path in vaultFiles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(path, style: th.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ),
                if (vaultFiles.isEmpty && savePath != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(savePath, style: th.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ),
              ],
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (vaultFiles.isNotEmpty)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _addLocalEncrypted(t, onAddedCallback: (enriched) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Torrent added and synced: ${enriched['title']}')),
                  );
                });
              },
              child: const Text('Add to session'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /* ── add local encrypted ───────────────────────────────── */
  Future<void> _addLocalEncrypted(
      Map<String, dynamic> t, {
        void Function(Map<String, dynamic> enriched)? onAddedCallback,
      }) async {
    final encPath = (t['vault_files'] as List?)?.first;
    if (encPath == null) return;

    try {
      final bytes = await File(encPath).readAsBytes();
      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain == null || plain.isEmpty) throw 'Decrypt failed';

      final infoHash = await _libtorrent.getInfoHashFromBytes(plain);
      if (infoHash == null) throw 'Invalid infoHash';

      // Check if already in libtorrent session (avoid duplicate add)
      final alreadyAdded = await _isTorrentAlreadyAdded(infoHash);
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

      final ip = await _getPublicIp();
      final ipEnc = ip != null
          ? base64Encode(CryptoHelper.encryptBytes(utf8.encode(ip)))
          : null;

      // Check if torrent already exists on Supabase
      final exists = await _doesSupabaseContainTorrent(infoHash);
      if (!exists) {
        final enriched = await _enrichTorrent(t);

        final torrentInsertResult = await Supabase.instance.client
            .from('torrents')
            .upsert({
          'info_hash': infoHash,
          'name': t['title'] ?? t['name'] ?? 'Unknown',
          'owner_id': user.id,
        })
            .select()
            .maybeSingle();

        if (torrentInsertResult == null) {
          throw Exception('Failed to insert torrent into Supabase');
        }

        final metaInsertResult = await Supabase.instance.client
            .from('torrent_metadata')
            .upsert({
          'info_hash': infoHash,
          'title': enriched?['title'] ?? 'Unknown',
          'artist': enriched?['artist'] ?? 'Unknown Artist',
          'album': enriched?['album'],
          'album_art_url': enriched?['album_art_url'],
        })
            .select()
            .maybeSingle();

        if (metaInsertResult == null) {
          throw Exception('Failed to insert metadata into Supabase');
        }
      } else {
        if (kDebugSwarmSupabase) {
          debugPrint('[SwarmView] Torrent already exists on Supabase, skipping upload.');
        }
      }

      try {
        await Supabase.instance.client
            .from('seeder_peers')
            .upsert({
          'user_id': user.id,
          'info_hash': infoHash,
          'ip_enc': ipEnc,
          'last_seen': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        throw Exception('Failed to upsert seeder peer: $e');
      }



      // Update local upload history
      if (_localUploadHistory.add(infoHash)) {
        await _saveLocalUploadHistory();
      }

      debugPrint('[SwarmView] Added torrent and peer: $infoHash');

      // ⬇️ After successful upload — fetch full torrent from Supabase & enrich
      try {
        final rows = await Supabase.instance.client
            .from('torrents')
            .select()
            .eq('info_hash', infoHash)
            .maybeSingle();

        if (rows != null) {
          final enriched = await _enrichTorrent(rows);
          if (enriched != null) {
            onAddedCallback?.call(enriched);

            // Add to _torrents list only if not present
            if (!_torrents.any((t) => t['info_hash'] == infoHash)) {
              setState(() {
                _torrents.add(enriched);
                _applySearch(notify: false);
              });
            }
          }
        }
      } catch (e, st) {
        debugPrint('[SwarmView] Post-upload fetch error: $e\n$st');
      }

    } catch (e, st) {
      debugPrint('[SwarmView] addLocalEncrypted error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding torrent: $e')),
        );
      }
    }
  }


/* ── supabase duplicate check helper ────────────────────── */
  Future<bool> _doesSupabaseContainTorrent(String infoHash) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('torrents')
          .select('info_hash')
          .eq('info_hash', infoHash)
          .limit(1);
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('[SwarmView] Supabase dup-check failed: $e');
      return false;
    }
  }


  /* ── helpers ───────────────────────────────────────────── */
  Future<bool> _isTorrentAlreadyAdded(String infoHash) async {
    try {
      return await _libtorrent.isTorrentActive(infoHash);
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getPublicIp() async {
    try {
      final res = await Supabase.instance.client.functions.invoke('getPublicIp');
      if (res.data != null && res.data is Map<String, dynamic>) {
        return res.data['ip'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /* ── search UI ─────────────────────────────────────────── */
  Widget buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        onChanged: (val) {
          _search = val;
          _applySearch();
        },
        decoration: const InputDecoration(
          hintText: 'Search torrents...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.black12,
        ),
      ),
    );
  }

  /* ── main build ────────────────────────────────────────── */
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isError
                ? Center(
              child: Text(
                'Error loading torrents.\nTry again later.',
                style: th.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            )
                : ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) => buildTorrentTile(_filtered[i], th),
            ),
          ),
        ],
      ),
    );
  }
}