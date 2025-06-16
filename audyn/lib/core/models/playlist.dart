import 'music_track.dart';

class Playlist {
  final String id;
  final String name;
  late final String folderPath; // local folder path where songs are stored
  List<MusicTrack> tracks;
  String? coverImagePath;

  Playlist({
    required this.id,
    required this.name,
    required this.folderPath,
    required this.tracks,

  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      folderPath: json['folderPath'] as String? ?? '',
      tracks: (json['tracks'] as List<dynamic>)
          .map((e) => MusicTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folderPath': folderPath,
    'tracks': tracks.map((e) => e.toJson()).toList(),
  };
}
