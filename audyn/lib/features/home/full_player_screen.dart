import 'package:audio_service/audio_service.dart';
import 'package:audyn/audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/playback/playback_manager.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  double _dragOffset = 0.0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final playbackManager = Provider.of<PlaybackManager>(context);
    final audioHandler = Provider.of<MyAudioHandler>(context, listen: false);
    final track = playbackManager.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Text('No track playing', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return GestureDetector(
      onVerticalDragStart: (_) => setState(() => _isDragging = true),
      onVerticalDragUpdate: (details) {
        setState(() {
          _dragOffset += details.delta.dy;
          if (_dragOffset > 150) {
            Navigator.pop(context);
          }
        });
      },
      onVerticalDragEnd: (_) {
        setState(() {
          _dragOffset = 0;
          _isDragging = false;
        });
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: _isDragging
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'albumArtHero',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: track.coverFile != null
                              ? Image.file(
                            track.coverFile!,
                            width: MediaQuery.of(context).size.width * 0.8,
                            height: MediaQuery.of(context).size.width * 0.8,
                            fit: BoxFit.cover,
                          )
                              : Icon(
                            Icons.music_note,
                            size: MediaQuery.of(context).size.width * 0.8,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.artist,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      _buildProgressBar(playbackManager),
                      const SizedBox(height: 32),
                      _buildPlaybackControls(audioHandler, playbackManager),
                      const SizedBox(height: 40),
                      _buildExtraControls(audioHandler, playbackManager),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(PlaybackManager playbackManager) {
    final duration = playbackManager.currentDuration ?? Duration.zero;
    final position = playbackManager.currentPosition ?? Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Slider(
            value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
            max: duration.inMilliseconds.toDouble(),
            onChanged: (value) {
              playbackManager.seek(Duration(milliseconds: value.toInt()));
            },
            activeColor: Colors.greenAccent,
            inactiveColor: Colors.white24,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControls(MyAudioHandler handler, PlaybackManager playbackManager) {
    final isPlaying = playbackManager.isPlaying;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 36,
          color: Colors.white70,
          icon: const Icon(Icons.skip_previous),
          onPressed: handler.skipToPrevious,
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 56,
          color: Colors.white,
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
          ),
          onPressed: () {
            isPlaying ? handler.pause() : handler.play();
          },
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 36,
          color: Colors.white70,
          icon: const Icon(Icons.skip_next),
          onPressed: handler.skipToNext,
        ),
      ],
    );
  }

  Widget _buildExtraControls(MyAudioHandler handler, PlaybackManager playbackManager) {
    final repeatMode = playbackManager.repeatMode;
    final shuffleEnabled = playbackManager.isShuffleEnabled;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            shuffleEnabled ? Icons.shuffle : Icons.shuffle_outlined,
            color: shuffleEnabled ? Colors.greenAccent : Colors.white70,
          ),
          onPressed: () {
            handler.setShuffleMode(
              shuffleEnabled
                  ? AudioServiceShuffleMode.none
                  : AudioServiceShuffleMode.all,
            );
          },
        ),
        const SizedBox(width: 48),
        IconButton(
          icon: Icon(
            repeatMode == RepeatMode.off
                ? Icons.repeat_outlined
                : repeatMode == RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: repeatMode == RepeatMode.off
                ? Colors.white70
                : Colors.greenAccent,
          ),
          onPressed: () {
            RepeatMode nextMode;
            switch (repeatMode) {
              case RepeatMode.off:
                nextMode = RepeatMode.all;
                break;
              case RepeatMode.all:
                nextMode = RepeatMode.one;
                break;
              case RepeatMode.one:
                nextMode = RepeatMode.off;
                break;
              case RepeatMode.group:
                throw UnimplementedError('Group repeat mode not supported.');
            }

            AudioServiceRepeatMode serviceMode;
            switch (nextMode) {
              case RepeatMode.off:
                serviceMode = AudioServiceRepeatMode.none;
                break;
              case RepeatMode.all:
                serviceMode = AudioServiceRepeatMode.all;
                break;
              case RepeatMode.one:
                serviceMode = AudioServiceRepeatMode.one;
                break;
              case RepeatMode.group:
                throw UnimplementedError('Group repeat mode not supported.');
            }

            handler.setRepeatMode(serviceMode);
          },
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
