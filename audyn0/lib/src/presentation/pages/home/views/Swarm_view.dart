import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
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

  List<Map<String, dynamic>> _torrents = [];
  bool _isLoading = true;
  bool _isError = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _seeder = await MusicSeederService.create();
      await _validateAndUploadLocalSongs();
      await _fetchSupabaseTorrents();
    } catch (e, st) {
      debugPrint('[SwarmView] init error: $e\n$st');
      setState(() => _isError = true);
    }
  }

  Future<void> _validateAndUploadLocalSongs() async {
    // 1) Request storage/audio permissions
    if (!await _audioQuery.permissionsRequest()) return;

    // 2) Query all on‑device songs
    final songs = await _audioQuery.querySongs();
    for (final song in songs) {
      // 3) Extract & validate metadata
      final meta = await _extractValidMetadata(song.data);
      if (meta == null) continue;

      // 4) Normalize the name
      final norm = MusicSeederService.norm(
        p.basenameWithoutExtension(song.data),
      );

      // 5) Seed _this_ one song, get back the encrypted torrent path
      final encryptedTorrentPath = await _seeder!.seedSong(song.data);
      if (encryptedTorrentPath == null) continue;

      // 6) Pull its info‐hash
      final infoHash = await _getInfoHashFromPath(encryptedTorrentPath);
      if (infoHash == null) continue;

      // 7) Start seeding
      await _libtorrent.startTorrentByHash(infoHash);

      // 8) Finally, upload both torrent record + metadata
      await _uploadToSupabase(infoHash, norm, meta);
    }
  }


  /// Extracts metadata if trackName, artist & albumArt are present
  Future<Metadata?> _extractValidMetadata(String filePath) async {
    try {
      final meta = await MetadataRetriever.fromFile(File(filePath));
      if ((meta.trackName?.isNotEmpty ?? false)
          && (meta.trackArtistNames?.isNotEmpty ?? false)
          && (meta.albumName?.isNotEmpty ?? false)
          && (meta.albumArt?.isNotEmpty ?? false)) {
        return meta;
      }
    } catch (_) { }
    return null;
  }

  Future<String?> _getInfoHashFromPath(String encPath) async {
    final bytes = await File(encPath).readAsBytes();
    final plain = CryptoHelper.decryptBytes(bytes);
    if (plain == null) return null;
    return await _libtorrent.getInfoHashFromDecryptedBytes(plain);
  }

  Future<void> _uploadToSupabase(String infoHash, String name, Metadata meta) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Upsert torrent
    await Supabase.instance.client
        .from('torrents')
        .upsert({
      'info_hash': infoHash,
      'name': name,
      'owner_id': user.id,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'info_hash');

    final albumArtBase64 = meta.albumArt != null
        ? base64Encode(meta.albumArt!)
        : null;

    // Upsert metadata
    await Supabase.instance.client
        .from('torrent_metadata')
        .upsert({
      'info_hash': infoHash,
      'title': meta.trackName,
      'artist': meta.trackArtistNames!.join(', '),
      'album': meta.albumName,
      'album_art_url': albumArtBase64,
    }, onConflict: 'info_hash');
  }

  /// 2) Fetch Supabase torrents + metadata
  Future<void> _fetchSupabaseTorrents() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      // NOTE: v2 API returns data directly or throws
      final data = await Supabase.instance.client
          .from('torrents')
          .select('info_hash, name, created_at, torrent_metadata(*)')
          .order('created_at', ascending: false)
          .limit(100);

      _torrents = List<Map<String, dynamic>>.from(data as List);

    } catch (e, st) {
      debugPrint('[SwarmView] fetch error: $e\n$st');
      setState(() => _isError = true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String v) {
    setState(() => _search = v.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _torrents.where((t) {
      final meta = t['torrent_metadata'] as Map? ?? {};
      final title = (meta['title'] as String?) ?? t['name'];
      final artist = (meta['artist'] as String?) ?? '';
      return title.toLowerCase().contains(_search)
          || artist.toLowerCase().contains(_search)
          || (t['name'] as String).toLowerCase().contains(_search);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swarm'),
        actions: [ IconButton(onPressed: _fetchSupabaseTorrents, icon: const Icon(Icons.refresh)) ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search torrents…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
          ? Center(child: Text('Error loading torrents', style: theme.textTheme.bodyLarge))
          : filtered.isEmpty
          ? Center(child: Text('No torrents found', style: theme.textTheme.bodyLarge))
          : ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final t = filtered[i];
          final meta = (t['torrent_metadata'] as Map?)?.cast<String, dynamic>() ?? {};

          final title = meta['title'] ?? t['name'];
          final artist = meta['artist'] ?? 'Unknown';
          final album = meta['album'] ?? '';
          final base64 = meta['album_art_url'] as String?;

          // Decode base64 to image
          Widget leading;
          if (base64 != null && base64.isNotEmpty) {
            try {
              final bytes = base64Decode(base64);
              leading = ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _defaultIcon(context), // Fallback to icon on error
                ),
              );
            } catch (e) {
              debugPrint('Album art decode error: $e');
              leading = _defaultIcon(context);
            }
          } else {
            leading = _defaultIcon(context);
          }

          // Determine trailing icon (status)
          final isSeeding = t['state'] == 5 || t['seed_mode'] == true;
          final isLocal = (t['vault_files'] as List?)?.isNotEmpty ?? false;

          Widget trailing;
          if (isLocal) {
            trailing = Icon(Icons.check_circle, color: Theme.of(context).colorScheme.secondary);
          } else if (isSeeding) {
            trailing = Icon(Icons.cloud_upload, color: Theme.of(context).colorScheme.primary);
          } else {
            trailing = Icon(Icons.cloud_download, color: Colors.grey.shade400);
          }

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: leading,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '$artist | $album',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: trailing,
            onTap: () {
              _libtorrent.startTorrentByHash(t['info_hash']);
            },
          );
        },

      ),
    );
  }
  Widget _defaultIcon(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_outlined, color: Colors.grey),
    );
  }

}
