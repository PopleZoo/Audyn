// ──────────────────────────────────────────────────────────────
//  SwarmView – shows local + remote torrents in the “Audyn” app
//  * Handles encrypted .audyn.torrent files in <app‑dir>/vault/
//  * Keeps a local cache of .torrent files in <app‑dir>/torrents/
//  * Works with the new LibtorrentService API you provided
// ──────────────────────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../../data/services/LibtorrentService.dart';

class SwarmView extends StatefulWidget {
  const SwarmView({Key? key}) : super(key: key);

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> {
  // ──────────────────────────  Services
  final LibtorrentService _libtorrent = LibtorrentService();
  final MusicSeederService _seeder = MusicSeederService();

  // ──────────────────────────  State
  List<Map<String, dynamic>> _torrents = [];
  List<Map<String, dynamic>> _filteredTorrents = [];
  final Map<String, Map<String, dynamic>> _metaCache = {};

  bool _isLoading = true;
  bool _isError = false;
  String _search = '';

  // ──────────────────────────  Lifecycle
  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  // ──────────────────────────  Helpers
  String? _artistFromName(String name) {
    final parts = name.split(' - ');
    return parts.isNotEmpty ? parts[0].trim() : null;
  }

  Future<List<String>> _vaultMatches(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final vault = Directory('${dir.path}/vault');
    if (!await vault.exists()) return [];

    return vault
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) =>
    f.path.toLowerCase().endsWith('.audyn.torrent') &&
        f.path.toLowerCase().contains(key.toLowerCase()))
        .map((f) => f.path)
        .toList();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      await _seeder.init();
      await _seeder.seedMissingSongs();
      await _fetchTorrents();
    } catch (e, st) {
      debugPrint('[SwarmView] refresh error: $e\n$st');
      setState(() {
        _isLoading = false;
        _isError = true;
      });
    }
  }

  // ──────────────────────────  Main fetch
  Future<void> _fetchTorrents() async {
    final List<Map<String, dynamic>> session = await _libtorrent.getAllTorrents();

    final docsDir = await getApplicationDocumentsDirectory();
    final torrentsDir = Directory(p.join(docsDir.path, 'torrents'));
    if (!await torrentsDir.exists()) await torrentsDir.create(recursive: true);

    final enriched = <Map<String, dynamic>>[];

    for (final t in session) {
      final name = (t['name'] ?? '').toString();
      if (name.isEmpty) continue;

      // 1️⃣  Cache .torrent on disk (plain)
      final torrentPath = p.join(torrentsDir.path, '$name.torrent');
      if (!File(torrentPath).existsSync()) {
        final bytes = await _libtorrent.createTorrentBytes(t['save_path'] ?? '');
        if (bytes != null) await File(torrentPath).writeAsBytes(bytes);
      }

      // 2️⃣  Metadata (memoised)
      if (!_metaCache.containsKey(name)) {
        final m = await _seeder.getMetadataForName(name);
        final author = t['author'] ?? '';
        final artistNames = t['artistnames'];
        String? artist;
        if (artistNames is List && artistNames.isNotEmpty) {
          artist = artistNames.join(', ');
        } else if (author is String && author.isNotEmpty) {
          artist = author;
        } else {
          artist = _artistFromName(name);
        }

        _metaCache[name] = {
          'meta_title': m?['title'] ?? name,
          'meta_artist': m?['artist']?.toString().isNotEmpty == true
              ? m!['artist']
              : (artist ?? 'Unknown Artist'),
          'meta_album': m?['album'] ?? '',
          'meta_albumArt': m?['albumArt'],
        };
      }

      // 3️⃣  Local encrypted .audyn.torrent presence
      final localEncrypted = await _vaultMatches(name);
      enriched.add({
        ...t,
        ..._metaCache[name]!,
        'file_found': localEncrypted.isNotEmpty,
        'local_files': localEncrypted,
      });
    }

    setState(() {
      _torrents = enriched;
      _applySearch();
      _isLoading = false;
    });
  }

  void _applySearch() {
    final q = _search.trim().toLowerCase();
    setState(() {
      _filteredTorrents = _torrents.where((t) {
        bool hit(String? v) => v?.toLowerCase().contains(q) ?? false;
        return hit(t['name']) ||
            hit(t['meta_title']) ||
            hit(t['meta_artist']) ||
            hit(t['meta_album']);
      }).toList();
    });
  }

  // ──────────────────────────  UI Parts
  Widget _searchField(ThemeData theme) => TextField(
    decoration: InputDecoration(
      hintText: 'Search torrents…',
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: Colors.white12,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
    ),
    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
    onChanged: (v) {
      _search = v;
      _applySearch();
    },
  );

  Widget _errorView(ThemeData theme) => Center(
    child: Text('Failed to load torrents.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
  );

  Widget _buildTile(Map<String, dynamic> t, ThemeData theme) {
    final bool isLocal = t['file_found'] == true;
    final bool isSeeding = (t['seed_mode'] == true) || (t['state'] == 5);

    Icon? icon;
    if (isLocal) {
      icon = Icon(Icons.check_circle, color: theme.colorScheme.secondary);
    } else if (isSeeding) {
      icon = Icon(Icons.upload, color: theme.colorScheme.primary);
    }

    return ListTile(
      leading: t['meta_albumArt'] != null
          ? Image.memory(t['meta_albumArt'], width: 50, height: 50, fit: BoxFit.cover)
          : const Icon(Icons.music_note, size: 32, color: Colors.white38),
      title: Text(t['meta_title'], maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(t['meta_artist'], maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: icon,
      onTap: () async {
        if (!isLocal) return;

        final encryptedPath = (t['local_files'] as List).first;
        try {
          final bytes = await File(encryptedPath).readAsBytes();
          final plain = CryptoHelper.decryptBytes(bytes);

          if (plain == null || plain.isEmpty) {
            throw Exception('Decrypted bytes are null or empty');
          }

          debugPrint('[SwarmView] Decrypted torrent bytes length: ${plain.length}');

          final dir = await getApplicationDocumentsDirectory();
          final added = await _libtorrent.addTorrentFromBytes(plain, dir.path, seedMode: false);

          if (!added) {
            throw Exception('Failed to add torrent from bytes');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added “${t['meta_title']}” to session.')),
            );
          }
        } catch (e, st) {
          debugPrint('[SwarmView] Error adding torrent: $e\n$st');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error adding torrent: $e')),
            );
          }
        }
      },
    );
  }

  Widget _listView(ThemeData theme) {
    if (_filteredTorrents.isEmpty) {
      return Center(
        child: Text('No torrents found.',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white54)),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView.separated(
        itemCount: _filteredTorrents.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (_, i) => _buildTile(_filteredTorrents[i], theme),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Audyn Swarm'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _isLoading ? null : _refreshAll),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(padding: const EdgeInsets.all(8.0), child: _searchField(theme)),
        ),
      ),
      body: _isLoading
          ? const _LoadingView()
          : _isError
          ? _errorView(theme)
          : _listView(theme),
    );
  }
}

// Simple loading view
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}
