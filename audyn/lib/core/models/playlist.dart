import 'music_track.dart';
class Playlist {
  final String id;
  final String name;
  final String folderPath; // you can remove `late` since you always require it
  List<MusicTrack> tracks; // make final to encourage immutability
  final String? coverImagePath;

  Playlist({
    required this.id,
    required this.name,
    required this.folderPath,
    List<MusicTrack>? tracks,
    this.coverImagePath,
  }) : tracks = tracks ?? [];

  // copyWith method to create a new Playlist with changed fields
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

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      folderPath: json['folderPath'] as String? ?? '',
      tracks: (json['tracks'] as List<dynamic>)
          .map((e) => MusicTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
      coverImagePath: json['coverImagePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folderPath': folderPath,
    'tracks': tracks.map((e) => e.toJson()).toList(),
    'coverImagePath': coverImagePath,
  };
}

