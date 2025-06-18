import 'dart:io';

import 'package:audyn/features/home/playlists_overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../../core/playlist/playlist_manager.dart';
import '../../core/models/music_track.dart';
import '../../core/playback/playback_manager.dart';
import '../player/Bottom_player.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistName;
  final Future<void> Function() onRescan;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistName,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final playlistManager = context.watch<PlaylistManager>();
    final playback = context.watch<PlaybackManager>();
    final playlists = playlistManager.playlists;

    final playlist = playlists.firstWhereOrNull((p) => p.name == playlistName);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Playlist has no songs")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // center vertically
            children: [
              const Text("Wow such empty"),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  await onRescan();
                },
                child: const Text("Rescan Music Directory"),
              ),
            ],
          ),
        ),
      );
    }


    final isPlaylistPlaying = playback.isPlaying &&
        const DeepCollectionEquality().equals(
          playback.currentTrack,
          playlist.tracks,
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Header with cover image
          FutureBuilder<String?>(
            future: File('${playlist.folderPath}/cover.jpg').exists().then(
                  (exists) => exists ? '${playlist.folderPath}/cover.jpg' : null,
            ),
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
                    Text(
                      playlist.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${playlist.tracks.length} tracks',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlueAccent,
                            foregroundColor: Colors.black,
                          ),
                          icon: Icon(
                            isPlaylistPlaying ? Icons.pause : Icons.play_arrow,
                          ),
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
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          icon: const Icon(Icons.shuffle),
                          label: const Text("Shuffle"),
                          onPressed: () {
                            playback.setPlaylist(playlist.tracks, shuffle: true);
                          },
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.sync, color: Colors.white70),
                          tooltip: 'Resync Playlist',
                            onPressed: () async {
                              await playlistManager.resyncPlaylist(playlist.name);
                            }
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // Divider
          const Divider(height: 1, color: Colors.white24),

          // Track list
          Expanded(
            child: playlist.tracks.isEmpty
                ? const Center(
              child: Text(
                "No tracks in this playlist.",
                style: TextStyle(color: Colors.white60),
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: playlist.tracks.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, indent: 80),
              itemBuilder: (context, i) {
                final MusicTrack track = playlist.tracks[i];
                final isPlaying = playback.currentTrack?.id == track.id && playback.isPlaying;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: track.coverUrl.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(track.coverUrl),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  )
                      : const Icon(Icons.music_note, size: 40, color: Colors.white70),
                  title: Text(track.title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(track.artist, style: const TextStyle(color: Colors.white54)),
                  trailing: IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        playback.pause();
                      } else {
                        playback.setPlaylist(playlist.tracks, shuffle: false);
                        playback.playTrack(track);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
