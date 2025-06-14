import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/music_track.dart';

class MusicBrainzAPI {
  static Future<List<MusicTrack>> search(String query) async {
    final uri = Uri.parse('https://musicbrainz.org/ws/2/recording?query=$query&fmt=json&limit=10');
    final res = await http.get(uri, headers: {
      'User-Agent': 'AudynPrototype/1.0.0 (your@email.com)',
    });

    final data = json.decode(res.body);
    final recordings = (data['recordings'] ?? []) as List;

    return Future.wait(recordings.map((r) async {
      final title = r['title'] ?? 'Unknown Title';
      final artist = (r['artist-credit']?[0]?['name']) ?? 'Unknown Artist';
      final id = r['id'];
      final releaseId = r['releases']?[0]?['id'];
      final coverUrl = releaseId != null
          ? await _fetchCoverUrl(releaseId)
          : '';


      return MusicTrack(
        id: id ?? '',
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        localPath: '',
      );
    }));
  }

  static Future<String> _fetchCoverUrl(String releaseId) async {
    final url = 'https://coverartarchive.org/release/$releaseId/front';
    final res = await http.get(Uri.parse(url));
    return res.statusCode == 200 ? url : '';
  }
}
