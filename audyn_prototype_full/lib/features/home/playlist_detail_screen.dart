import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import '../../core/models/playlist.dart';
import '../../core/playlist/playlist_manager.dart';
import '../../core/models/music_track.dart';
import '../../core/playback/playback_manager.dart'; // <-- Import the playback manager

class PlaylistDetailScreen extends StatelessWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistManager>().playlists;
    final playback = context.watch<PlaybackManager>();
    final playlist = playlists.firstWhereOrNull((p) => p.id == playlistId);

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Playlist Not Found")),
        body: const Center(child: Text("The playlist you're looking for doesn't exist.")),
      );
    }

    final currentTrack = playback.currentTrack;

    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: playlist.tracks.isEmpty
          ? const Center(child: Text("No tracks in this playlist."))
          : ListView.builder(
        itemCount: playlist.tracks.length,
        itemBuilder: (context, i) {
          final track = playlist.tracks[i];
          final isPlaying = currentTrack?.id == track.id && playback.isPlaying;

          return ListTile(
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
                : const Icon(Icons.music_note, size: 40),
            title: Text(track.title),
            subtitle: Text(track.artist),
            trailing: IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle : Icons.play_circle,
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
      floatingActionButton: FloatingActionButton.extended(
        label: const Text("Shuffle Play"),
        icon: const Icon(Icons.shuffle),
        onPressed: () {
          playback.setPlaylist(playlist.tracks, shuffle: true);
        },
      ),
    );
  }
}
