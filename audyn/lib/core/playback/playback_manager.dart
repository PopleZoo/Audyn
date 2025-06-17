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

  int get currentIndex => _currentIndex;

  // === LOGIC ===

  /// Sets the current playlist and optionally shuffles it.
  /// If the same playlist is already loaded, resumes playing.
  Future<void> setPlaylist(
      List<MusicTrack> tracks, {
        bool shuffle = false,
        String? playlistId,
      }) async {
    // If the playlist is the same and not empty, just resume playing
    if (_currentPlaylistId == playlistId && _playlist.isNotEmpty) {
      await _audioHandler.play();
      return;
    }

    _playlist = List.of(tracks);
    _isShuffled = shuffle;
    _currentPlaylistId = playlistId;
    _currentIndex = 0;

    if (playlistId != null) {
      _playlistShuffleStates[playlistId] = shuffle;
    }

    if (_playlist.isEmpty) {
      debugPrint('[PlaybackManager] Attempted to set an empty playlist.');
      return;
    }

    if (shuffle) {
      _originalOrder = List.of(_playlist);
      _playlist.shuffle();
    } else {
      _originalOrder = null;
    }

    await _playCurrent();
    notifyListeners();
  }

  /// Plays the track at the current index.
  Future<void> _playCurrent() async {
    if (_currentIndex >= 0 && _currentIndex < _playlist.length) {
      final track = _playlist[_currentIndex];
      if (track.localPath != null) {
        await _audioHandler.playTrack(track.localPath!);
      }
    }
  }

  /// Plays a specific track if it exists in the current playlist.
  Future<void> playTrack(MusicTrack track) async {
    final index = _playlist.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      _currentIndex = index;
      await _playCurrent();
    }
  }

  Future<void> pause() => _audioHandler.pause();

  Future<void> play() => _audioHandler.play();

  Future<void> seek(Duration position) => _audioHandler.seek(position);

  Future<void> next() async {
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      await _playCurrent();
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await _playCurrent();
      notifyListeners();
    }
  }

  /// Toggles shuffle on/off for the current playlist in memory.
  void toggleShuffle() {
    _isShuffled = !_isShuffled;

    if (_isShuffled) {
      _originalOrder = List.of(_playlist);
      _playlist.shuffle();
    } else if (_originalOrder != null) {
      _playlist = List.of(_originalOrder!);
      _originalOrder = null;
    }

    // Keep the shuffle state map in sync
    if (_currentPlaylistId != null) {
      _playlistShuffleStates[_currentPlaylistId!] = _isShuffled;
    }

    notifyListeners();
  }

  /// Toggles shuffle state flag for a specific playlist (does not reorder tracks).
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
