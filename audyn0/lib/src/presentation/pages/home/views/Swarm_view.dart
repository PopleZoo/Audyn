// lib/src/presentation/pages/home/views/Swarm_view.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../../data/services/LibtorrentService.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

/*─────────────────────────────────────────────────────────────*
│  SwarmView – nicer tiles + dialog                            │
*─────────────────────────────────────────────────────────────*/
class SwarmView extends StatefulWidget {
  const SwarmView({Key? key}) : super(key: key);

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  /* services */
  final _libtorrent = LibtorrentService();
  final _seeder     = MusicSeederService();

  /* data cache */
  final _metaCache  = <String, Map<String, dynamic>>{};
  final _torrents   = <Map<String, dynamic>>[];
  var   _filtered   = <Map<String, dynamic>>[];
  var   _vault      = <String, List<String>>{};

  /* ui‑state */
  var _isLoading = true;
  var _isError   = false;
  var _search    = '';

  @override
  void initState() {
    super.initState();
    _loadOnce();
  }

  /* ───────────────────── load session once ───────────────────── */

  Future<void> _loadOnce() async {
    try {
      await _seeder.init();
      _vault = await _indexVault();

      final cacheDir  = _seeder.torrentsDir!;
      final session   = await _libtorrent.getAllTorrents();

      for (final t in session) {
        final enriched = await _enrichTorrent(t, cacheDir);
        if (enriched != null) _torrents.add(enriched);
      }
      _applySearch(notify: false);
    } catch (e, st) {
      debugPrint('[SwarmView] load error: $e\n$st');
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
      final name = p.basenameWithoutExtension(f.path.replaceAll('.audyn',''));
      out.putIfAbsent(name, () => []).add(f.path);
    }
    return out;
  }
  Future<Map<String, dynamic>?> _enrichTorrent(
      Map<String, dynamic> t, Directory cacheDir) async {

    final name = (t['name'] ?? '').toString();
    if (name.isEmpty) return null;

    /* 1. keep local .torrent cache … unchanged … */

    /* 2. memoised metadata -------------------------------------------- */
    if (!_metaCache.containsKey(name)) {
      final m = await _seeder.getMetadataForName(name);

      String resolveArtist() {
        final lst = t['artistnames'];
        if (lst is List && lst.isNotEmpty) return lst.join(', ');
        final author = t['author']?.toString() ?? '';
        if (author.isNotEmpty) return author;
        final parts = name.split(' - ');
        return parts.isNotEmpty ? parts[0] : 'Unknown Artist';
      }

      _metaCache[name] = {
        'title'  : (m?['title']  ?? name).toString(),
        'artist' : (m?['artist'] ?? resolveArtist()).toString(),
        'album'  : (m?['album']  ?? '').toString(),
        'art'    : m?['albumArt'],          // might be null, fill below
      };
    }

    /* 3.  try to fill missing album‑art on‑demand ---------------------- */
    if (_metaCache[name]!['art'] == null) {
      // Assume single‑file torrent: <save_path>/<name>
      final baseDir   = t['save_path']?.toString() ?? '';
      final candidate = File(p.join(baseDir, name));
      if (await candidate.exists()) {
        try {
          final meta = await MetadataRetriever.fromFile(candidate);
          if (meta.albumArt != null) {
            _metaCache[name]!['art'] = meta.albumArt;
          }
        } catch (_) {/* ignore – leave art null */}
      }
    }

    /* 4. return enriched map ------------------------------------------ */
    return {
      ...t,
      ..._metaCache[name]!,
      'vault_files': _vault[name] ?? [],
    };
  }


  /* search filter */
  void _applySearch({bool notify = true}) {
    final q = _search.trim().toLowerCase();
    _filtered = _torrents.where((t) {
      bool hit(String? s) => s?.toLowerCase().contains(q) ?? false;
      return hit(t['name']) ||
          hit(t['title'])||
          hit(t['artist'])||
          hit(t['album']);
    }).toList();
    if (notify && mounted) setState((){});
  }

  /* ───────────────────── tile & dialog helpers ───────────────────── */

  Widget buildTorrentTile(Map<String, dynamic> t, ThemeData th) {
    // ── SAFE lookup ──────────────────────────────────────────────
    final localFiles = (t['vault_files'] as List?) ?? const <String>[];
    final isLocal    = localFiles.isNotEmpty;
    final isSeeding  = (t['seed_mode'] == true) || (t['state'] == 5);

    return ListTile(
      leading: t['art'] != null
          ? Image.memory(t['art'], width: 50, height: 50, fit: BoxFit.cover)
          : const Icon(Icons.music_note, size: 32, color: Colors.white38),

      title: Text(t['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(t['artist']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),

      trailing: Icon(
        isLocal   ? Icons.check_circle
            : isSeeding ? Icons.cloud_upload : Icons.cloud_download,
        color: isLocal   ? th.colorScheme.secondary
            : isSeeding ? th.colorScheme.primary
            : Colors.white38,
      ),
      onTap: () => showTorrentDialog(t, th),
    );
  }

  void showTorrentDialog(Map<String, dynamic> t, ThemeData th) {
    final vaultFiles = (t['vault_files'] as List<String>?) ?? [];
    final playlists  = t['playlists'] as List<String>? ?? [];
    final artBytes   = t['art'];

    final isSeeding  = t['state'] == 5 || t['seed_mode'] == true;
    final isLocal    = isSeeding || vaultFiles.isNotEmpty;
    final savePath   = t['save_path']?.toString();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: const EdgeInsets.all(16),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Cover Art ──────────────────────────────────────
              if (artBytes is Uint8List)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    artBytes,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                )
              else
                const Icon(Icons.music_note, size: 100, color: Colors.white38),

              const SizedBox(height: 12),

              // ── Metadata ───────────────────────────────────────
              Text(
                t['title']?.toString() ?? 'Unknown',
                style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Artist: ${t['artist'] ?? 'Unknown'}',
                textAlign: TextAlign.center,
              ),
              if ((t['album']?.toString().isNotEmpty ?? false))
                Text(
                  'Album: ${t['album']}',
                  textAlign: TextAlign.center,
                ),

              const SizedBox(height: 12),

              // ── Local Status ───────────────────────────────────
              Chip(
                label: Text(isLocal ? 'Stored locally' : 'Remote only'),
                backgroundColor: isLocal
                    ? th.colorScheme.secondary.withOpacity(.2)
                    : Colors.grey.shade800,
              ),

              // ── Storage Paths ─────────────────────────────────
              if (isLocal) ...[
                const SizedBox(height: 10),
                Text(
                  'Storage location${(vaultFiles.length > 1 || savePath != null) ? 's' : ''}:',
                  style: th.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                // Vault file paths (if any)
                for (final path in vaultFiles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      path,
                      style: th.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Seeding path (if not in vault)
                if (vaultFiles.isEmpty && savePath != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      savePath,
                      style: th.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],

              // ── Playlists ─────────────────────────────────────
              if (playlists.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Playlists:',
                  style: th.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  children: playlists.map((pl) => Chip(label: Text(pl))).toList(),
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





  Future<void> _addLocalEncrypted(Map<String,dynamic> t) async {
    final encPath = (t['vault_files'] as List?)?.first;
    if (encPath == null) return; // or handle error
    try {
      final bytes = await File(encPath).readAsBytes();
      final plain = CryptoHelper.decryptBytes(bytes);
      if (plain==null || plain.isEmpty) throw 'decrypt failed';

      final dir   = await getApplicationDocumentsDirectory();
      final ok    = await _libtorrent.addTorrentFromBytes(
          plain, dir.path, seedMode:false);
      if (!ok) throw 'native add failed';

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content:Text('Added “${t['title']}”.')));
      }
    } catch (e,st) {
      debugPrint('[SwarmView] add error $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content:Text('Error: $e')));
      }
    }
  }

  /* ───────────────────── ui build ───────────────────── */

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      backgroundColor: th.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText:'Search torrents…',
                prefixIcon: const Icon(Icons.search),
                filled:true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                    borderRadius:BorderRadius.circular(22),
                    borderSide:BorderSide.none),
                contentPadding:const EdgeInsets.symmetric(vertical:10),
              ),
              style: th.textTheme.bodyMedium?.copyWith(color:Colors.white70),
              onChanged:(v){ _search=v; _applySearch(); },
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child:CircularProgressIndicator())
          : _isError
          ? Center(child:Text('Failed to load torrents.',
          style: th.textTheme.bodyMedium
              ?.copyWith(color:th.colorScheme.error)))
          : _filtered.isEmpty
          ? Center(child:Text('No torrents found.',
          style: th.textTheme.titleMedium
              ?.copyWith(color: Colors.white54)))
          : ListView.separated(
        itemCount: _filtered.length,
        separatorBuilder: (_,__) =>
        const Divider(height:1, color:Colors.white12),
        itemBuilder: (_,i) => buildTorrentTile(_filtered[i], th),
      ),
    );
  }
}
