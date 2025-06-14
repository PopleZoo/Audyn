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
      await _player.setUrl(uri);
      await _player.play();
    } catch (e) {
      print("Error playing track: $e");
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

// 🔑 This stays OUTSIDE the class
Future<MyAudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.audyn_prototype.channel.audio',
      androidNotificationChannelName: 'Audio Playback',
      androidNotificationOngoing: true,
    ),
  );
}
