import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

class SongMetadata {
  final String infoHash;
  final String title;
  final String artist;
  final String? album;
  final String? albumArtUrl;

  SongMetadata({
    required this.infoHash,
    required this.title,
    required this.artist,
    this.album,
    this.albumArtUrl,
  });

  factory SongMetadata.fromMap(Map<String, dynamic> map) {
    return SongMetadata(
      infoHash: map['info_hash'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String?,
      albumArtUrl: map['album_art_url'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'info_hash': infoHash,
      'title': title,
      'artist': artist,
      'album': album,
      'album_art_url': albumArtUrl,
    };
  }
}

class SwarmMetadataService {
  final bool useMock;

  SwarmMetadataService({this.useMock = true});

  Future<SongMetadata?> getMetadataByHash(String infoHash) async {
    if (useMock) {
      final mockData = _mockDb[infoHash];
      if (mockData != null) {
        return SongMetadata.fromMap(mockData);
      }
      return null;
    }

    try {
      final response = await Supabase.instance.client
          .from('torrent_metadata')
          .select()
          .eq('info_hash', infoHash)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return SongMetadata.fromMap(response as Map<String, dynamic>);
    } catch (e, st) {
      log('Exception in getMetadataByHash: $e\n$st');
      return null;
    }
  }

  Future<void> upsertMetadata(SongMetadata metadata) async {
    if (useMock) {
      _mockDb[metadata.infoHash] = metadata.toMap();
      log('Mock: Upserted metadata for ${metadata.title}');
      return;
    }

    try {
      await Supabase.instance.client
          .from('torrent_metadata')
          .upsert(metadata.toMap());
      log('Supabase upsertMetadata success for ${metadata.title}');
    } catch (e, st) {
      log('Exception in upsertMetadata: $e\n$st');
    }
  }

  Future<List<SongMetadata>> getAllMetadata() async {
    if (useMock) {
      return _mockDb.values.map((e) => SongMetadata.fromMap(e)).toList();
    }

    try {
      final response = await Supabase.instance.client
          .from('torrent_metadata')
          .select();

      final dataList = response as List<dynamic>;

      return dataList
          .map((e) => SongMetadata.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      log('Exception in getAllMetadata: $e\n$st');
      return [];
    }
  }

  static final Map<String, Map<String, dynamic>> _mockDb = {
    'cc0136fb8649e421362222599eea284bb386d932': {
      'info_hash': 'cc0136fb8649e421362222599eea284bb386d932',
      'title': '18',
      'artist': 'Anarbor',
      'album': 'Burnout',
      'album_art_url': null,
    },
    'e702ff417f6bacca652543b5c2d6688b9f5c4c3c': {
      'info_hash': 'e702ff417f6bacca652543b5c2d6688b9f5c4c3c',
      'title': '1950',
      'artist': 'King Princess',
      'album': 'Make My Bed',
      'album_art_url': null,
    },
    'd4478e8b118481313af9205c3f01f0745765941f': {
      'info_hash': 'd4478e8b118481313af9205c3f01f0745765941f',
      'title': '24K Magic',
      'artist': 'Bruno Mars',
      'album': '24K Magic',
      'album_art_url': null,
    },
  };
}
