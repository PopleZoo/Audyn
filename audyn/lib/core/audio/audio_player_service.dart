import 'package:audioplayers/audioplayers.dart';
import '../models/music_track.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;

  late final AudioPlayer _audioPlayer;
  AudioPlayer get audioPlayer => _audioPlayer; // optional getter

  AudioPlayerService._internal() {
    _audioPlayer = AudioPlayer();
  }

  Future<void> playTrack(MusicTrack track) async {
    final path = track.localPath;
    if (path == null || path.isEmpty) {
      throw ArgumentError('Cannot play track: localPath is null or empty');
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    await _audioPlayer.resume();
  }
}
