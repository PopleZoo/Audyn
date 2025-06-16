import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../../core/playback/playback_manager.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  DateTime? _lastTap;

  void _handlePrevious(PlaybackManager playbackManager) {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(seconds: 1)) {
      // Double-tap detected
      playbackManager.previous();
    } else {
      // Single tap: restart track
      playbackManager.seekToStart();
    }
    _lastTap = now;
  }

  void _showFullCover(BuildContext context, File coverFile) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(coverFile, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playbackManager = Provider.of<PlaybackManager>(context);
    final track = playbackManager.currentTrack;

    if (track == null) return const Scaffold();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Now Playing"),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Album Cover
          GestureDetector(
            onTap: () {
              if (track.coverFile != null) {
                _showFullCover(context, track.coverFile!);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: track.coverFile != null
                    ? Image.file(
                  track.coverFile!,
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.width * 0.8,
                  fit: BoxFit.cover,
                )
                    : Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.width * 0.8,
                  color: Colors.grey[800],
                  child: const Icon(Icons.music_note, color: Colors.white, size: 60),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Title & Artist
          Text(
            track.title ?? "Unknown Title",
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            track.artist ?? "Unknown Artist",
            style: const TextStyle(color: Colors.white70, fontSize: 18),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                onPressed: () => _handlePrevious(playbackManager),
              ),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 56,
                icon: Icon(
                  playbackManager.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: Colors.white,
                ),
                onPressed: () => playbackManager.isPlaying
                    ? playbackManager.pause()
                    : playbackManager.play(),
              ),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed: playbackManager.next,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
