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
              // Close Button
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
                          child: Image.file(
                            track.coverFile!,
                            width: MediaQuery.of(context).size.width * 0.8,
                            height: MediaQuery.of(context).size.width * 0.8,
                            fit: BoxFit.cover,
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

                      // Progress Bar with time
                      _buildProgressBar(playbackManager),

                      const SizedBox(height: 32),

                      // Playback controls
                      _buildPlaybackControls(playbackManager),

                      const SizedBox(height: 40),

                      // Extra controls (shuffle, repeat)
                      _buildExtraControls(playbackManager),
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

  Widget _buildPlaybackControls(PlaybackManager playbackManager) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 36,
          color: Colors.white70,
          icon: const Icon(Icons.skip_previous),
          onPressed: playbackManager.previous,
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 56,
          color: Colors.white,
          icon: Icon(
            playbackManager.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
          ),
          onPressed: () {
            playbackManager.isPlaying ? playbackManager.pause() : playbackManager.play();
          },
        ),
        const SizedBox(width: 32),
        IconButton(
          iconSize: 36,
          color: Colors.white70,
          icon: const Icon(Icons.skip_next),
          onPressed: playbackManager.next,
        ),
      ],
    );
  }

  Widget _buildExtraControls(PlaybackManager playbackManager) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            playbackManager.isShuffleEnabled ? Icons.shuffle : Icons.shuffle_outlined,
            color: playbackManager.isShuffleEnabled ? Colors.greenAccent : Colors.white70,
          ),
          onPressed: playbackManager.toggleShuffle,
        ),
        const SizedBox(width: 48),
        IconButton(
          icon: Icon(
            playbackManager.repeatMode == RepeatMode.off
                ? Icons.repeat_outlined
                : playbackManager.repeatMode == RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            color: playbackManager.repeatMode == RepeatMode.off ? Colors.white70 : Colors.greenAccent,
          ),
          onPressed: playbackManager.cycleRepeatMode,
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final secondsStr = seconds.toString().padLeft(2, '0');
    return '$minutes:$secondsStr';
  }
}
