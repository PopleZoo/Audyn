import 'music_track.dart';

class Playlist {
  final String id;
  final String name;
  final String folderPath;
  List<MusicTrack> _tracks;  // private backing field for tracks
  final String? coverImagePath;

  Playlist({
    required this.id,
    required this.name,
    required this.folderPath,
    List<MusicTrack>? tracks,  // allow nullable for optional default empty list
    this.coverImagePath,
  }) : _tracks = tracks ?? [];

  // Getter for tracks
  List<MusicTrack> get tracks => _tracks;

  // Setter for tracks
  set tracks(List<MusicTrack> newTracks) {
    _tracks = newTracks;
  }

  // copyWith method to create a new Playlist with updated fields
  Playlist copyWith({
    String? id,
    String? name,
    String? folderPath,
    List<MusicTrack>? tracks,
    String? coverImagePath,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      folderPath: folderPath ?? this.folderPath,
      tracks: tracks ?? this.tracks,
      coverImagePath: coverImagePath ?? this.coverImagePath,
    );
  }

  // JSON deserialization factory
  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      folderPath: json['folderPath'] as String? ?? '',
      tracks: (json['tracks'] as List<dynamic>?)
          ?.map((e) => MusicTrack.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      coverImagePath: json['coverImagePath'] as String?,
    );
  }

  // JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folderPath': folderPath,
    'tracks': tracks.map((e) => e.toJson()).toList(),
    'coverImagePath': coverImagePath,
  };
}
