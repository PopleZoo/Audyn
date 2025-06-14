import 'package:flutter/material.dart';
import '../../audio_handler.dart';
import '../models/music_track.dart';
import '../models/playlist.dart';

class PlaybackManager extends ChangeNotifier {
  final MyAudioHandler _audioHandler;

  List<MusicTrack> _playlist = [];
  List<MusicTrack>? _originalOrder;
  int _currentIndex = -1;
  bool _isShuffled = false;

  final Map<String, bool> _playlistShuffleStates = {};
  String? _currentPlaylistId;

  PlaybackManager(this._audioHandler);

  // === GETTERS ===

  bool get isPlaying => _audioHandler.playbackState.value.playing;

  MusicTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  bool get shuffleEnabled => _isShuffled;
  String? get currentPlaylistId => _currentPlaylistId;

  // === LOGIC ===

  Future<void> setPlaylist(List<MusicTrack> tracks,
      {bool shuffle = false, String? playlistId}) async {
    if (_currentPlaylistId == playlistId && _playlist.isNotEmpty) {
      await _audioHandler.play();
      return;
    }

    _playlist = List.from(tracks);
    _isShuffled = shuffle;
    _currentPlaylistId = playlistId;
    _currentIndex = 0;

    if (playlistId != null) {
      _playlistShuffleStates[playlistId] = shuffle;
    }

    if (shuffle) {
      _originalOrder = List.from(_playlist);
      _playlist.shuffle();
    }

    await _playCurrent();
    notifyListeners();
  }

  Future<void> _playCurrent() async {
    if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
      final track = _playlist[_currentIndex];
      await _audioHandler.playTrack(track.localPath!);
    }
  }

  Future<void> playTrack(MusicTrack track) async {
    final index = _playlist.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      _currentIndex = index;
      await _playCurrent();
    }
  }

  Future<void> pause() => _audioHandler.pause();
  Future<void> play() => _audioHandler.play();
  Future<void> seek(Duration pos) => _audioHandler.seek(pos);

  Future<void> next() async {
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      await _playCurrent();
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await _playCurrent();
    }
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;

    if (_isShuffled) {
      _originalOrder = List.from(_playlist);
      _playlist.shuffle();
    } else if (_originalOrder != null) {
      _playlist = List.from(_originalOrder!);
    }

    notifyListeners();
  }

  void toggleShuffleForPlaylist(Playlist playlist) {
    final current = _playlistShuffleStates[playlist.id] ?? false;
    _playlistShuffleStates[playlist.id] = !current;
    notifyListeners();
  }

  Future<void> seekToStart() async {
    await _audioHandler.seek(Duration.zero);
  }

  bool isPlaylistPlaying(Playlist playlist) =>
      _audioHandler.playbackState.value.playing &&
          _currentPlaylistId == playlist.id;

  bool isCurrentPlaylist(Playlist playlist) =>
      _currentPlaylistId == playlist.id;

  bool isPlaylistShuffled(Playlist playlist) =>
      _playlistShuffleStates[playlist.id] ?? false;

  Future<void> resume() async {
    await _audioHandler.play();
  }

}
