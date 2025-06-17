import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MyAudioHandler() {
    // Broadcast playback state changes
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });

    // Update mediaItem when current index changes
    _player.currentIndexStream.listen((index) {
      final sequence = _player.sequence;
      if (index != null && sequence != null && index < sequence.length) {
        final tag = sequence[index].tag;
        if (tag is MediaItem) {
          mediaItem.add(tag);
        }
      }
    });

    // Listen for player state changes for error handling or idle state
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.idle && !state.playing) {
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ));
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: _mapJustAudioRepeatModeToAudioService(_player.loopMode),
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  AudioServiceRepeatMode _mapJustAudioRepeatModeToAudioService(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return AudioServiceRepeatMode.none;
      case LoopMode.one:
        return AudioServiceRepeatMode.one;
      case LoopMode.all:
        return AudioServiceRepeatMode.all;
    }
  }

  LoopMode _mapAudioServiceRepeatModeToJustAudio(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.none:
        return LoopMode.off;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
      case AudioServiceRepeatMode.all:
        return LoopMode.all;
      case AudioServiceRepeatMode.group:
        throw UnimplementedError('Group repeat mode is not supported');
    }
  }

  // Optional streams you can expose if needed
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> playTrack(
      String uri, {
        String? title,
        String? artist,
        String? album,
        Uri? artUri,
      }) async {
    final item = MediaItem(
      id: uri,
      title: title ?? 'Unknown Title',
      artist: artist ?? 'Unknown Artist',
      album: album ?? 'Unknown Album',
      artUri: artUri ??
          Uri.parse(
            'https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Black_square.jpg/120px-Black_square.jpg',
          ),
    );

    try {
      final source = AudioSource.uri(Uri.parse(uri), tag: item);
      await _player.setAudioSource(source);
      await setQueue([item]); // Important for skip controls to work
      await setMediaItem(item);
      await _player.play();
    } catch (e) {
      print('❌ Error in playTrack: $e');
    }
  }

  // === Playback Commands ===
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    final loopMode = _mapAudioServiceRepeatModeToJustAudio(mode);
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: mode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    final enableShuffle = mode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enableShuffle);
    if (enableShuffle) {
      await _player.shuffle();
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: mode));
  }

  @override
  Future<void> setQueue(List<MediaItem> items) async {
    queue.add(items);
  }

  @override
  Future<void> setMediaItem(MediaItem item) async {
    mediaItem.add(item);
  }
}
Future<MyAudioHandler> initAudioService() async {
  final handler = MyAudioHandler();
  await AudioService.init(
    builder: () => handler,
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.example.audyn.channel.audio',
      androidNotificationChannelName: 'Audyn Playback',
      androidNotificationOngoing: true,
    ),
  );
  debugPrint("✅ AudioHandler initialized: $handler");
  return handler;
}
