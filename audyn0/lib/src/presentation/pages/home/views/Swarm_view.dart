import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../services/music_seeder_service.dart';
import '../../../../../utils/CryptoHelper.dart';
import '../../../../bloc/Downloads/DownloadsBloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../data/services/LibtorrentService.dart';

class _UploadItem {
  final String infoHash;
  final String name;
  final Metadata meta;

  _UploadItem(this.infoHash, this.name, this.meta);
}

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
  Set<String> _localSongKeys = {};

  List<_UploadItem> _supabaseUploadQueue = [];

  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  final int _pageSize = 50;
  bool _isLoadingMore = false;
  bool _hasMore = true;


  @override
  void initState() {
    super.initState();
    _init();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
  }


  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      await _fetchSupabaseTorrents(); // fetch Supabase data first, show list quickly
    } catch (e, st) {
      debugPrint('[SwarmView] fetchSupabaseTorrents error: $e\n$st');
      setState(() => _isError = true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    // Now start seeding local songs in the background, no UI block
    try {
      _seeder = await MusicSeederService.create();
      // run seeding without awaiting UI-wise, but handle errors inside
      _validateAndUploadLocalSongs();
    } catch (e, st) {
      debugPrint('[SwarmView] validateAndUploadLocalSongs error: $e\n$st');
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _currentPage++;

    try {
      final data = await Supabase.instance.client
          .from('torrents')
          .select('info_hash, name, created_at, torrent_metadata(title, artist, album, album_art_url)')
          .order('created_at', ascending: false)
          .range(_currentPage * _pageSize, _currentPage * _pageSize + _pageSize - 1);

      final fetched = List<Map<String, dynamic>>.from(data as List);
      if (fetched.isEmpty) {
        _hasMore = false;
      } else {
        setState(() => _torrents.addAll(fetched));
      }
    } catch (e, st) {
      debugPrint('[SwarmView] loadMore error: $e\n$st');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }


  Future<void> _validateAndUploadLocalSongs() async {
    if (!await _audioQuery.permissionsRequest()) return;

    final songs = await _audioQuery.querySongs();
    final existingSongPaths = songs.map((s) => s.data).toSet();

    // Clean orphaned torrent files
    final seededTorrents = await _seeder!.getAllSeededTorrents();
    for (final encTorrentPath in seededTorrents) {
      final base = p.basenameWithoutExtension(encTorrentPath);
      final norm = MusicSeederService.norm(base);

      final isStillPresent = existingSongPaths.any((sp) =>
      MusicSeederService.norm(p.basenameWithoutExtension(sp)) == norm);

      if (!isStillPresent) {
        final infoHash = await _getInfoHashFromPath(encTorrentPath);
        if (infoHash != null) {
          await _libtorrent.removeTorrent(infoHash, removeData: false);

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await Supabase.instance.client
                .from('seeder_peers')
                .delete()
                .match({'info_hash': infoHash, 'user_id': user.id});
          }
        }

        try {
          await File(encTorrentPath).delete();
          debugPrint('[Cleanup] Deleted orphaned torrent: $encTorrentPath');
        } catch (e) {
          debugPrint('[Cleanup] Failed to delete: $encTorrentPath\n$e');
        }
      }
    }

    // Seed valid songs, defer uploads
    for (final song in songs) {
      final meta = await _extractValidMetadata(song.data);
      if (meta == null) continue;

      final normKey = MusicSeederService.norm(p.basenameWithoutExtension(song.data));
      _localSongKeys.add(normKey);

      final encryptedTorrentPath = await _seeder!.seedSong(song.data);
      if (encryptedTorrentPath == null) continue;

      final infoHash = await _getInfoHashFromPath(encryptedTorrentPath);
      if (infoHash == null) continue;

      await _libtorrent.startTorrentByHash(infoHash);
      _supabaseUploadQueue.add(_UploadItem(infoHash, normKey, meta));
    }

    await _runSupabaseUploads();
  }

  Future<void> _runSupabaseUploads() async {
    final total = _supabaseUploadQueue.length;
    if (total == 0) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    for (final item in _supabaseUploadQueue) {
      try {
        final existing = await Supabase.instance.client
            .from('torrent_metadata')
            .select('title, artist, album, album_art_url')
            .eq('info_hash', item.infoHash)
            .maybeSingle();

        if (existing is! Map) continue;

        final encodedArt = item.meta.albumArt != null
            ? base64Encode(item.meta.albumArt!)
            : null;

        final alreadyUploaded = existing != null &&
            existing['title'] == item.meta.trackName &&
            existing['artist'] == item.meta.trackArtistNames?.join(', ') &&
            existing['album'] == item.meta.albumName &&
            existing['album_art_url'] == encodedArt;

        if (!alreadyUploaded) {
          await _uploadToSupabase(item.infoHash, item.name, item.meta);
        }
      } catch (e) {
        debugPrint('[Upload] Skipped failed upload for ${item.name}: $e');
      }

    }

    _supabaseUploadQueue.clear();
  }



  /// Extracts metadata if trackName, artist & albumArt are present
  Future<Metadata?> _extractValidMetadata(String filePath) async {
    try {
      final meta = await MetadataRetriever.fromFile(File(filePath));
      if ((meta.trackName?.isNotEmpty ?? false) &&
          (meta.trackArtistNames?.isNotEmpty ?? false) &&
          (meta.albumName?.isNotEmpty ?? false) &&
          ((meta.albumArt?.isNotEmpty ?? false))) {
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

    final now = DateTime.now().toIso8601String();

    // Upsert torrent
    await Supabase.instance.client
        .from('torrents')
        .upsert({
      'info_hash': infoHash,
      'name': name,
      'owner_id': user.id,
      'created_at': now,
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
      'artist': meta.trackArtistNames?.join(', ') ?? '',
      'album': meta.albumName,
      'album_art_url': albumArtBase64,
    }, onConflict: 'info_hash');
    // Also upsert into `seeder_peers`
    final ip = await _getLocalIp();
    final ipEnc = ip != null ? CryptoHelper.encryptString(ip) : null;

    if (ipEnc != null) {
      await Supabase.instance.client
          .from('seeder_peers')
          .upsert({
        'user_id': user.id,
        'info_hash': infoHash,
        'last_seen': now,
        'ip_enc': ipEnc,
      }, onConflict: 'user_id,info_hash');
    }

  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[SwarmView] Failed to get local IP: $e');
    }
    return null;
  }

  Future<void> _fetchSupabaseTorrents({
    int pageNumber = 0,
    int pageSize = 50,
  }) async {
    if (pageNumber == 0) {
      _currentPage = 0;
      _hasMore = true;
    }

    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      debugPrint('Fetching torrents, page: $pageNumber, size: $pageSize');

      final query = Supabase.instance.client
          .from('torrents')
          .select('info_hash, name, created_at, torrent_metadata(title, artist, album, album_art_url)')
          .order('created_at', ascending: false)
          .range(pageNumber * pageSize, pageNumber * pageSize + pageSize - 1);

      final data = await query;
      debugPrint('Fetched ${data.length} records from Supabase.');

      final fetched = List<Map<String, dynamic>>.from(data as List);

      if (pageNumber == 0) {
        _torrents = fetched;
      } else {
        _torrents.addAll(fetched);
      }

      if (fetched.length < pageSize) {
        _hasMore = false;
        debugPrint('No more torrents to load.');
      }
    } catch (e, st) {
      debugPrint('[SwarmView] fetchSupabaseTorrents error: $e\n$st');
      setState(() => _isError = true);
    } finally {
      setState(() => _isLoading = false);
    }
  }


  void _onSearchChanged(String value) {
    setState(() {
      _search = value.trim().toLowerCase();
    });
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
        controller: _scrollController,
        itemCount: filtered.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= filtered.length) {
            // Show loading indicator at the bottom while loading more
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final t = filtered[index];
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
          final torrentNameKey = MusicSeederService.norm(t['name'] as String? ?? '');
          final isSeeding = t['state'] == 5 || t['seed_mode'] == true;
          final isLocal = _localSongKeys.contains(torrentNameKey)
              || ((t['vault_files'] as List?)?.isNotEmpty ?? false);

          Widget trailing;
          if (isLocal) {
            trailing = Icon(Icons.check_circle, color: theme.colorScheme.secondary);
          } else if (isSeeding) {
            trailing = Icon(Icons.cloud_upload, color: theme.colorScheme.primary);
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
              showTorrentDialog(context, t,_localSongKeys);
            },
          );
        },

      ),
    );
  }

  Widget _defaultIcon(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_outlined, color: Colors.grey),
    );
  }


  Future<void> showTorrentDialog(BuildContext context, Map<String, dynamic> torrent, Set<String> localSongKeys) async {
    final theme = Theme.of(context);
    final meta = (torrent['torrent_metadata'] as Map<String, dynamic>?) ?? {};
    final title = meta['title'] ?? torrent['name'] ?? 'Unknown';
    final artist = meta['artist'] ?? 'Unknown Artist';
    final album = meta['album'] ?? 'Unknown Album';
    final artBase64 = meta['album_art_url'] as String?;

    Widget leading;
    if (artBase64 != null && artBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(artBase64);
        leading = Image.memory(
          bytes,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
        );
      } catch (_) {
        leading = Icon(Icons.broken_image, size: 100, color: theme.colorScheme.onSurface.withOpacity(0.3));
      }
    } else {
      leading = Icon(Icons.music_note, size: 100, color: theme.colorScheme.onSurface.withOpacity(0.3));
    }

    // Normalize torrent name to compare with local song keys
    final torrentNameKey = MusicSeederService.norm(torrent['name'] as String? ?? '');

    final bool isSeeding = torrent['state'] == 5 || torrent['seed_mode'] == true;
    final bool isLocal = localSongKeys.contains(torrentNameKey)
        || ((torrent['vault_files'] as List?)?.isNotEmpty ?? false);

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: 16),
              Text('Artist: $artist'),
              Text('Album: $album'),
              const SizedBox(height: 24),
              if (isLocal) Text('You already have this song stored locally.', style: TextStyle(color: Colors.green)),
              if (isSeeding) Text('You are currently seeding this song.', style: TextStyle(color: Colors.blue)),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(isLocal || isSeeding ? 'Cannot Download' : 'Start Download'),
              onPressed: (isLocal || isSeeding)
                  ? null
                  : () {
                final infoHash = torrent['info_hash'] ?? '';
                if (infoHash.isEmpty) return;

                final title = (torrent['torrent_metadata'] as Map<String, dynamic>?)?['title'] ?? torrent['name'] ?? '';
                final artist = (torrent['torrent_metadata'] as Map<String, dynamic>?)?['artist'] ?? 'Unknown Artist';
                final album = (torrent['torrent_metadata'] as Map<String, dynamic>?)?['album'] ?? 'Unknown Album';

                Uint8List? art;
                final artBase64 = (torrent['torrent_metadata'] as Map<String, dynamic>?)?['album_art_url'] as String?;
                if (artBase64 != null && artBase64.isNotEmpty) {
                  try {
                    art = base64Decode(artBase64);
                  } catch (_) {}
                }

                final savePath = '/storage/emulated/0/Download/music'; // adjust as needed

                context.read<DownloadsBloc>().add(
                  DownloadRequested(
                    infoHash: infoHash,
                    name: torrent['name'] ?? '',
                    title: title,
                    artist: artist,
                    album: album,
                    albumArt: art,
                    filePath: savePath,
                  ),
                );

                Navigator.of(context).pop();
              },
            ),

          ],
        );
      },
    );
  }



}
