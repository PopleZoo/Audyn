// lib/src/presentation/pages/home/views/Swarm_view.dart

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

const bool kDebugSwarmSupabase = true; // Set to false in production

class SwarmView extends StatefulWidget {
  const SwarmView({Key? key}) : super(key: key);

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  final _libtorrent = LibtorrentService();
  final _seeder     = MusicSeederService();

  final _metaCache = <String, Map<String, dynamic>>{};
  final _torrents  = <Map<String, dynamic>>[];
  var   _filtered  = <Map<String, dynamic>>[];
  var   _vault     = <String, List<String>>{};

  var _isLoading = true;
  var _isError   = false;
  var _search    = '';


  @override
  void initState() {
    super.initState();
    _refresh();
  }

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

      // Capture newly created torrent file paths from seeding
      final newlySeeded = await _seeder.seedMissingSongs();
      debugPrint('[SwarmView] Seeded ${newlySeeded.length} new torrents');

      // Index vault files after seeding
      _vault = await _indexVault();

      // Auto-add and upload newly seeded torrents to libtorrent and Supabase
      for (final path in newlySeeded) {
        final name = p.basenameWithoutExtension(path.replaceAll('.audyn.torrent', ''));
        final norm = MusicSeederService.norm(name);

        // Compose minimal torrent map for _addLocalEncrypted
        final torrent = {
          'name': name,
          'vault_files': [path],
        };

        // Add and upload each new torrent
        await _addLocalEncrypted(torrent);
      }

      // Load current torrents from libtorrent session
      final session = await _libtorrent.getAllTorrents();
      debugPrint('[SwarmView] Loaded ${session.length} torrents');

      for (final t in session) {
        final enriched = await _enrichTorrent(t);
        if (enriched != null) _torrents.add(enriched);
      }

      _applySearch(notify: false);
    } catch (e, st) {
      debugPrint('[SwarmView] refresh error: $e\n$st');
      _isError = true;
    }

    if (mounted) setState(() => _isLoading = false);
  }


  Future<Map<String, List<String>>> _indexVault() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory(p.join(base.path, 'vault'));
    if (!await dir.exists()) return {};

    final out = <String, List<String>>{};
    await for (final f in dir.list(recursive: true)) {
      if (f is! File || !f.path.endsWith('.audyn.torrent')) continue;
      final name = p.basenameWithoutExtension(f.path.replaceAll('.audyn', ''));
      out.putIfAbsent(name, () => []).add(f.path);
    }
    return out;
  }

  Future<Map<String, dynamic>?> _enrichTorrent(Map<String, dynamic> t) async {
    final name = t['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    final norm = MusicSeederService.norm(name);

    if (!_metaCache.containsKey(norm)) {
      final m = await _seeder.getMetadataForName(name);
      _metaCache[norm] = {
        'title'       : (m?['title']       ?? name).toString(),
        'artist'      : (m?['artist']      ?? 'Unknown Artist').toString(),
        'artistnames' : (m?['artistnames'] ?? []),
        'album'       : (m?['album']       ?? 'Unknown').toString(),
        'art'         : m?['albumArt'],
      };
    }


    // On-demand load album art
    if (_metaCache[norm]!['art'] == null) {
      final baseDir = t['save_path']?.toString() ?? '';
      final candidate = File(p.join(baseDir, name));
      if (await candidate.exists()) {
        try {
          final meta = await MetadataRetriever.fromFile(candidate);
          if (meta.albumArt != null) {
            _metaCache[norm]!['art'] = meta.albumArt;
          }
        } catch (_) {}
      }
    }

    return {
      ...t,
      ..._metaCache[norm]!,
      'vault_files': _vault[norm] ?? [],
    };
  }

  void _applySearch({bool notify = true}) {
    final q = _search.trim().toLowerCase();
    _filtered = _torrents.where((t) {
      bool hit(String? s) => s?.toLowerCase().contains(q) ?? false;
      return hit(t['name']) || hit(t['title']) ||
          hit(t['artist']) || hit(t['album']);
    }).toList();

    if (notify && mounted) setState(() {});
  }

  Widget buildTorrentTile(Map<String, dynamic> t, ThemeData th) {
    final isLocal   = (t['vault_files'] as List?)?.isNotEmpty ?? false;
    final isSeeding = (t['seed_mode'] == true) || (t['state'] == 5);

    return ListTile(
      leading: t['art'] != null
          ? Image.memory(t['art'], width: 50, height: 50, fit: BoxFit.cover)
          : const Icon(Icons.music_note, size: 32, color: Colors.white38),
      title: Text(t['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        (t['artistnames'] as List?)?.join(', ') ?? t['artist'] ?? 'Unknown',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        isLocal ? Icons.check_circle
            : isSeeding ? Icons.cloud_upload : Icons.cloud_download,
        color: isLocal ? th.colorScheme.secondary
            : isSeeding ? th.colorScheme.primary
            : Colors.white38,
      ),
      onTap: () => showTorrentDialog(t, th),
    );
  }

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
                Text('Storage location${vaultFiles.length > 1 || savePath != null ? 's' : ''}:',
                    style: th.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
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
                await _addLocalEncrypted(t);
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

  Future<void> _addLocalEncrypted(Map<String, dynamic> t) async {
    final encPath = (t['vault_files'] as List?)?.first;
    if (encPath == null) return;

    try {
      final bytes = await File(encPath).readAsBytes();
      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain == null || plain.isEmpty) throw 'Decrypt failed';

      final dir = await getApplicationDocumentsDirectory();
      final ok = await _libtorrent.addTorrentFromBytes(plain, dir.path, seedMode: true);
      if (!ok) throw 'Failed to add torrent to session';

      // Get info-hash
      final infoHash = await _libtorrent.getInfoHashFromBytes(plain);
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null || infoHash == null) throw 'User not signed in or infoHash missing';

      // Fetch public IP
      final ip = await _getPublicIp();
      if (ip == null) throw 'Could not determine IP';
      final ipEnc = base64Encode(CryptoHelper.encryptBytes(utf8.encode(ip)));

      // Insert into `torrents` table first (to satisfy FK constraint)
      await Supabase.instance.client.from('torrents').upsert({
        'info_hash': infoHash,
        'name': t['title'] ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Insert into `seeder_peers` table
      final payload = {
        'user_id': user.id,
        'info_hash': infoHash,
        'ip_enc': ipEnc,
        'last_seen': DateTime.now().toIso8601String(),
      };

      if (kDebugSwarmSupabase) {
        debugPrint('[SwarmView] Upserting → seeder_peers: $payload');
      }

      final response = await Supabase.instance.client
          .from('seeder_peers')
          .upsert(payload)
          .select();

      if (kDebugSwarmSupabase) {
        debugPrint('[SwarmView] Supabase response: $response');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added “${t['title']}” and synced with swarm.')),
        );
      }
    } catch (e, st) {
      debugPrint('[SwarmView] _addLocalEncrypted error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding torrent: $e')),
        );
      }
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


  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      backgroundColor: th.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refresh,
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search torrents…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: th.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              onChanged: (v) {
                _search = v;
                _applySearch();
              },
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
          ? Center(child: Text('Failed to load torrents.', style: th.textTheme.bodyMedium?.copyWith(color: th.colorScheme.error)))
          : _filtered.isEmpty
          ? Center(child: Text('No torrents found.', style: th.textTheme.titleMedium?.copyWith(color: Colors.white54)))
          : RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
          itemBuilder: (_, i) => buildTorrentTile(_filtered[i], th),
        ),
      ),
    );
  }
}
