import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MyAudioHandler() {
    // Broadcast playback state changes
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });

    // Broadcast current media item changes when audio source changes
    _player.currentIndexStream.listen((index) {
      if (index != null && index < (_player.sequence?.length ?? 0)) {
        final source = _player.sequence![index];
        if (source.tag is MediaItem) {
          mediaItem.add(source.tag as MediaItem);
        }
      }
    });

    // Broadcast duration changes
    _player.durationStream.listen((duration) {
      // No built-in mediaItem duration update in audio_service,
      // but you can update your UI if needed by exposing durationStream.
    });
  }

  /// Converts just_audio's PlaybackEvent into audio_service's PlaybackState
  PlaybackState _transformEvent(PlaybackEvent event) {
    final processingState = _player.processingState;
    AudioProcessingState audioProcessingState;

    switch (processingState) {
      case ProcessingState.idle:
        audioProcessingState = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        audioProcessingState = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        audioProcessingState = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        audioProcessingState = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        audioProcessingState = AudioProcessingState.completed;
        break;
    }

    return PlaybackState(
      controls: [
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToPrevious,
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
      processingState: audioProcessingState,
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

  // Helpers to map just_audio <-> audio_service repeat modes
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
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  // Expose position & duration streams for external use
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Play a single track from URI with optional metadata
  Future<void> playTrack(String uri,
      {String? title,
        String? artist,
        String? album,
        Uri? artUri}) async {
    final mediaItem = MediaItem(
      id: uri,
      album: album ?? "Unknown Album",
      title: title ?? "Unknown Title",
      artist: artist ?? "Unknown Artist",
      artUri: artUri ??
          Uri.parse(
              "https://upload.wikimedia.org/wikipedia/commons/thumb/4/45/Black_square.jpg/120px-Black_square.jpg"),
    );

    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri), tag: mediaItem));
      this.mediaItem.add(mediaItem);
      await _player.play();
    } catch (e) {
      print("❌ Error playing track: $e");
    }
  }

  // === Override AudioHandler methods ===

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

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
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = _mapAudioServiceRepeatModeToJustAudio(repeatMode);
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enableShuffle = shuffleMode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enableShuffle);

    // When enabling shuffle, shuffle the queue
    if (enableShuffle) {
      await _player.shuffle();
    }

    playbackState.add(playbackState.value.copyWith(
      shuffleMode: shuffleMode,
    ));
  }
}

// Singleton-safe global handler
MyAudioHandler? _audioHandlerInstance;
bool _isAudioServiceInitializing = false;

/// Initialize AudioService and return singleton handler instance
Future<MyAudioHandler> initAudioService() async {
  if (_audioHandlerInstance != null) return _audioHandlerInstance!;

  if (_isAudioServiceInitializing) {
    while (_audioHandlerInstance == null) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return _audioHandlerInstance!;
  }

  _isAudioServiceInitializing = true;

  try {
    _audioHandlerInstance = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.audyn_prototype.channel.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e) {
    print('❌ Error initializing AudioService: $e');
    // Fallback: manually create instance without initializing AudioService
    if (_audioHandlerInstance == null) {
      print("⚠️ Falling back to manual handler creation.");
      _audioHandlerInstance = MyAudioHandler();
    } else {
      rethrow;
    }
  } finally {
    _isAudioServiceInitializing = false;
  }

  return _audioHandlerInstance!;
}
