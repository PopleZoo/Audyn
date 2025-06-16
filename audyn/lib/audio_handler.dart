import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    final audioProcessingState = () {
      switch (_player.processingState) {
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
    }();

    return PlaybackState(
      controls: [
        MediaControl.pause,
        MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
        MediaControl.skipToPrevious,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: audioProcessingState,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: null,
    );
  }

  Future<void> playTrack(String uri) async {
    try {
      final mediaItem = MediaItem(
        id: uri,
        album: "Unknown Album",
        title: "Unknown Title",
        artist: "Unknown Artist",
        artUri: Uri.parse("https://example.com/artwork.png"), // Optional
      );

      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(uri), tag: mediaItem),
      );

      this.mediaItem.add(mediaItem);

      await _player.play();
    } catch (e) {
      print("❌ Error playing track: $e");
    }
  }


  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.dispose();
    return super.stop();
  }
}

// ✅ Singleton-safe global handler
MyAudioHandler? _audioHandlerInstance;
bool _isAudioServiceInitializing = false;

/// ✅ Initialize only once safely
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
    // This call will fail if already initialized
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

    // Fail-safe fallback: assume it’s already initialized
    if (_audioHandlerInstance == null) {
      print("⚠️ Falling back to assuming existing handler.");
      // Build manually without reinitializing AudioService
      _audioHandlerInstance = MyAudioHandler();
    } else {
      rethrow;
    }
  } finally {
    _isAudioServiceInitializing = false;
  }

  return _audioHandlerInstance!;
}
