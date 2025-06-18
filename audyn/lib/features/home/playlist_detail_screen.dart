import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../../core/playlist/playlist_manager.dart';
import '../../core/models/music_track.dart';
import '../../core/playback/playback_manager.dart';
import '../../widget/track_list_item.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistName;
  final Future<void> Function() onRescan;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistName,
    required this.onRescan,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  static const bool isDebug = false;
  static const int maxVisibleTracks = 300;

  String _searchQuery = '';
  String _sortBy = 'Title';
  bool _ascending = true;
  bool _isShuffleActive = false;

  Future<String?> _getCoverPath(String folderPath) async {
    final coverFile = File('$folderPath/cover.jpg');
    return await coverFile.exists() ? coverFile.path : null;
  }

  Future<bool> _fileExists(String path) async {
    return await File(path).exists();
  }

  List<MusicTrack> _applyFilters(List<MusicTrack> tracks) {
    var filtered = tracks.where((track) {
      return track.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          track.artist.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      int compare;
      switch (_sortBy) {
        case 'Artist':
          compare = a.artist.compareTo(b.artist);
          break;
        case 'Date Added':
          final aDate = a.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
          compare = aDate.compareTo(bDate);
          break;
        case 'Title':
        default:
          compare = a.title.compareTo(b.title);
      }
      return _ascending ? compare : -compare;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final playlistManager = context.watch<PlaylistManager>();
    final playlists = playlistManager.playlists;
    final playlist = playlists.firstWhereOrNull((p) => p.name == widget.playlistName);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Playlist has no songs")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Wow such empty"),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async => await widget.onRescan(),
                child: const Text("Rescan Music Directory"),
              ),
            ],
          ),
        ),
      );
    }

    final visibleTracks = isDebug
        ? playlist.tracks.take(maxVisibleTracks).toList()
        : playlist.tracks;

    final displayedTracks = _applyFilters(visibleTracks);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          FutureBuilder<String?>(
            future: _getCoverPath(playlist.folderPath),
            builder: (context, snapshot) {
              final coverPath = snapshot.data;
              return Container(
                padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 20),
                decoration: BoxDecoration(
                  image: coverPath != null
                      ? DecorationImage(
                    image: FileImage(File(coverPath)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.5),
                      BlendMode.darken,
                    ),
                  )
                      : null,
                  color: Colors.grey[900],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            playlist.name,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${playlist.tracks.length} tracks',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    Selector<PlaybackManager, bool>(
                      selector: (_, pm) => pm.isPlaying &&
                          const DeepCollectionEquality().equals(
                            pm.currentTrack,
                            playlist.tracks,
                          ),
                      builder: (context, isPlaylistPlaying, _) {
                        final playback = context.read<PlaybackManager>();
                        return Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.lightBlueAccent,
                                foregroundColor: Colors.black,
                              ),
                              icon: Icon(isPlaylistPlaying ? Icons.pause : Icons.play_arrow),
                              label: Text(isPlaylistPlaying ? "Pause" : "Play"),
                              onPressed: () {
                                if (isPlaylistPlaying) {
                                  playback.pause();
                                } else {
                                  playback.setPlaylist(playlist.tracks, shuffle: false);
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            Ink(
                              decoration: BoxDecoration(
                                color: _isShuffleActive
                                    ? Colors.lightBlueAccent.withOpacity(0.3)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.shuffle,
                                  color: _isShuffleActive
                                      ? Colors.lightBlueAccent
                                      : Colors.white,
                                  size: 24,
                                ),
                                onPressed: () async {
                                  setState(() {
                                    _isShuffleActive = !_isShuffleActive;
                                  });
                                  await playback.setPlaylist(
                                    playlist.tracks,
                                    shuffle: _isShuffleActive,
                                    playlistId: playlist.name,
                                  );
                                },
                                tooltip: 'Shuffle Play',
                                splashRadius: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.sync, color: Colors.white70),
                              tooltip: 'Resync Playlist',
                              onPressed: () async {
                                await playlistManager.resyncPlaylist(playlist.name);
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(height: 1, color: Colors.white24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search tracks...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    DropdownButton<String>(
                      value: _sortBy,
                      dropdownColor: Colors.black,
                      style: const TextStyle(color: Colors.white),
                      items: ['Title', 'Artist', 'Date Added'].map((e) {
                        return DropdownMenuItem(
                          value: e,
                          child: Text(e),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sortBy = value);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        color: Colors.white,
                      ),
                      onPressed: () => setState(() => _ascending = !_ascending),
                      tooltip: 'Toggle Sort Direction',
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              cacheExtent: 500,
              itemCount: displayedTracks.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, indent: 80),
              itemBuilder: (context, i) {
                final track = displayedTracks[i];
                return TrackListItem(track: track, fullPlaylist: playlist.tracks);
              },

            ),
          ),
        ],
      ),
    );
  }
}
