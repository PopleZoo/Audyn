import 'dart:io';
import 'package:audyn/features/home/playlist_detail_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audyn/utils/playlist_cover_generator.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../../core/models/music_track.dart';
import '../../core/models/playlist.dart';
import '../../core/playback/playback_manager.dart';
import '../../core/playlist/playlist_manager.dart';


class PlaylistsOverviewScreen extends StatefulWidget {
  const PlaylistsOverviewScreen({Key? key}) : super(key: key);

  @override
  State<PlaylistsOverviewScreen> createState() => _PlaylistsOverviewScreenState();
}

class _PlaylistsOverviewScreenState extends State<PlaylistsOverviewScreen> {
  final List<String> recentlyPlayed = [];
  final List<Playlist> recentPlaylists = [];

  List<Playlist> playlists = [];
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;
  String _error = '';

  final Color spotifyGreenStart = Colors.lightBlueAccent;
  final Color spotifyGreenEnd = Colors.lightBlueAccent;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playlistManager = Provider.of<PlaylistManager>(context, listen: false);
      playlistManager.resyncPlaylists();
    });

    _scanMusicDirectory();
  }


  Future<void> _scanMusicDirectory() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    if (kIsWeb) {
      setState(() {
        _error = 'Storage access is not supported on Web.';
        _loading = false;
      });
      return;
    }

    try {
      Directory? musicDir;

      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final appMusicDir = Directory('${extDir.path}/AudynMusic');
          if (!await appMusicDir.exists()) {
            await appMusicDir.create(recursive: true);
          }
          musicDir = appMusicDir;
        }
      } else if (Platform.isIOS) {
        musicDir = await getApplicationDocumentsDirectory();
      } else {
        throw Exception('Unsupported platform');
      }

      if (musicDir == null || !await musicDir.exists()) {
        throw Exception('Music directory not found.');
      }

      final foundPlaylists = await _scanPlaylists(musicDir);
      setState(() {
        playlists = foundPlaylists;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: ${e.toString()}';
        _loading = false;
      });
    }
  }
  String generateUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  Future<List<Playlist>> _scanPlaylists(Directory dir) async {
    final List<Playlist> found = [];
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;
          // Create Playlist with unique id and empty tracks for now
          found.add(Playlist(id: generateUniqueId(), name: folderName, tracks: [], folderPath: dir.toString()));
        } else if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (ext == 'm3u' || ext == 'pls') {
            final fileName = entity.path.split(Platform.pathSeparator).last;
            found.add(Playlist(id: generateUniqueId(), name: fileName, tracks: [], folderPath: dir.toString()));
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning playlists: $e');
    }
    return found;
  }


  List<Playlist> filteredPlaylists(String query) {
    if (query.isEmpty) return playlists;

    final lowerQuery = query.toLowerCase();

    return playlists.where((playlist) {
      return playlist.name.toLowerCase().contains(lowerQuery);
    }).toList();
  }



  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openPlaylist(Playlist playlist) {
    setState(() {
      recentPlaylists.remove(playlist.name);
      recentPlaylists.insert(0, playlist);
      if (recentPlaylists.length > 10) {
        recentPlaylists.removeLast();
      }
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playlistName: playlist.name,
          onRescan: () async {
            await _scanMusicDirectory();
          },
        ),
      ),
    );

  }

  void _openRecentlyPlayed(String title) {
    _showSnackBar('Playing recently played: $title');
  }

  Future<void> _showCreatePlaylistDialog() async {
    String newPlaylistName = '';
    final formKey = GlobalKey<FormState>();
    final playlistManager = context.read<PlaylistManager>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Create New Playlist',
            style: TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Playlist Name',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.lightBlueAccent),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a name';
                }
                if (playlists.contains(value.trim())) {
                  return 'Playlist already exists';
                }
                return null;
              },
              onChanged: (value) => newPlaylistName = value,
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent,
              ),
              child: const Text('Create'),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(context).pop();
                  await _createPlaylist(newPlaylistName.trim());
                  await playlistManager.resyncPlaylists();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _createPlaylist(String name) async {
    Directory? musicDir;

    try {
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          musicDir = Directory('${extDir.path}/AudynMusic');
        }
      } else if (Platform.isIOS) {
        musicDir = await getApplicationDocumentsDirectory();
      }

      if (musicDir != null) {
        final playlistDir = Directory('${musicDir.path}/$name');

        List<MusicTrack> scannedTracks = [];

        if (await playlistDir.exists()) {
          // Folder exists - scan for songs
          scannedTracks = await scanFolderForTracks(playlistDir);
        } else {
          // Folder does not exist - create it
          await playlistDir.create(recursive: true);
        }

        // Create playlist object (assuming you have a Playlist class)
        final newPlaylist = Playlist(
          id: generateUniqueId(),
          name: name,
          folderPath: playlistDir.path,
          tracks: scannedTracks,
        );

        // Add to your playlists list
        setState(() {
          playlists.add(newPlaylist);
        });

        _showSnackBar('Playlist "$name" created with ${scannedTracks.length} tracks.');

        await generatePlaylistCover(playlistDir.path);
      } else {
        _showSnackBar('Error: Could not determine music directory.');
      }
    } catch (e) {
      debugPrint('Error creating playlist folder: $e');
      _showSnackBar('Error creating playlist folder.');
    }
  }

// Helper function to scan folder for music files
  Future<List<MusicTrack>> scanFolderForTracks(Directory folder) async {
    final List<MusicTrack> foundTracks = [];

    final files = folder.listSync(recursive: true);
    for (var file in files) {
      if (file is File) {
        final ext = path.extension(file.path).toLowerCase();
        if (['.mp3', '.wav', '.flac', '.m4a'].contains(ext)) {
          foundTracks.add(MusicTrack(
            id: file.path,
            title: path.basenameWithoutExtension(file.path),
            artist: 'Unknown', // Optional: add metadata extraction here
            localPath: file.path,
            coverUrl: '',
          ));
        }
      }
    }

    return foundTracks;
  }
  Widget _buildPlaylistTile(Playlist _playlist) {
    return Consumer2<PlaylistManager, PlaybackManager>(
        builder: (context, playlistManager, playback, _) {
          final matchingPlaylists = playlistManager.playlists.where((p) => p.name == _playlist.name);

          if (matchingPlaylists.isEmpty) {
            return SizedBox.shrink(); // or any placeholder widget
          }

          final playlist = matchingPlaylists.first;


          if (playlist == null) {
            return SizedBox.shrink();
          }

          final isPlaylistPlaying = playback.isPlaying && playback.currentPlaylistId == playlist.name;

          return FutureBuilder<File?>(
            future: _getPlaylistCover(playlist.name).catchError((_) => null),
            builder: (context, snapshot) {
              final coverFile = snapshot.data;
              return Material(
                key: ValueKey(coverFile?.path),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.hardEdge,
                child: coverFile != null
                    ? Ink.image(
                  image: FileImage(coverFile),
                  fit: BoxFit.cover,
                  height: 120,
                  child: InkWell(
                    onTap: () => _openPlaylist(playlist),
                    child: _buildTileOverlay(playlist, playback, isPlaylistPlaying),
                  ),
                )
                    : InkWell(
                  onTap: () => _openPlaylist(playlist),
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        _buildTileOverlay(playlist, playback, isPlaylistPlaying),
                        const Center(
                          child: Icon(
                            Icons.music_note,
                            size: 60,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }
    );
  }



  Future<File> _getPlaylistCover(String playlistName) async {
    Directory? musicDir;

    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) musicDir = Directory('${extDir.path}/AudynMusic');
    } else if (Platform.isIOS) {
      musicDir = await getApplicationDocumentsDirectory();
    }

    if (musicDir == null) throw Exception('Music directory not found');

    final cover = File('${musicDir.path}/$playlistName/cover.jpg');
    if (!await cover.exists()) throw Exception('Cover not found');

    return cover;
  }

  Widget _buildCreatePlaylistTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _showCreatePlaylistDialog,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: spotifyGreenStart),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 48, color: spotifyGreenStart),
            const SizedBox(height: 8),
            Text(
              'Create Playlist',
              style: TextStyle(
                color: spotifyGreenStart,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistsGrid() {
    final tiles = <Widget>[_buildCreatePlaylistTile()];
    tiles.addAll(filteredPlaylists(searchQuery).map(_buildPlaylistTile));

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, index) => tiles[index],
    );
  }


  Widget _buildRecentPlaylistsSection() {
    final uniqueRecent = recentPlaylists.toSet().toList();

    if (uniqueRecent.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Playlists',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: uniqueRecent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final name = uniqueRecent[index];
              return SizedBox(
                width: 160,
                child: _buildPlaylistTile(name),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildPlaylistsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playlists',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => searchQuery = value),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search playlists',
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white12,
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(color: spotifyGreenStart),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
        ),
        const SizedBox(height: 16),
        _buildPlaylistsGrid(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Playlists',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
              ? Center(
            child: Text(
              _error,
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          )
              : ListView(
            children: [
              _buildRecentPlaylistsSection(),
              const SizedBox(height: 32),
              _buildPlaylistsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildTileOverlay(Playlist playlist, PlaybackManager playback, bool isPlaylistPlaying) {
  return Stack(
    children: [
      // Dark overlay
      Positioned.fill(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.6),
                Colors.black.withOpacity(0.3),
                Colors.transparent,
              ],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ),
      ),

      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playlist title
            Text(
              playlist.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),

            const SizedBox(height: 4),

            // Track count
            Text(
              '${playlist.tracks.length} tracks',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),

            const Spacer(),

            // Buttons (play / shuffle)
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Play / Pause
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.lightBlueAccent,
                  child: IconButton(
                    icon: Icon(
                      isPlaylistPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black87,
                      size: 22,
                    ),
                    onPressed: () async {
                      if (isPlaylistPlaying) {
                        await playback.pause();
                      } else {
                        await playback.setPlaylist(
                          playlist.tracks,
                          shuffle: false,
                          playlistId: playlist.name,
                        );
                      }
                    },
                    tooltip: isPlaylistPlaying ? 'Pause' : 'Play',
                  ),
                ),
                const Spacer(),

                // Shuffle
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white24,
                  child: IconButton(
                    icon: const Icon(Icons.shuffle, color: Colors.white, size: 20),
                    onPressed: () async {
                      await playback.setPlaylist(
                        playlist.tracks,
                        shuffle: true,
                        playlistId: playlist.name,
                      );
                    },
                    tooltip: 'Shuffle Play',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}