import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

enum SortOption {
  popularity,
  seedCount,
  releaseCount,
  titleAsc,
  titleDesc,
}

SortOption _selectedSortOption = SortOption.releaseCount;

class PopularTracksManager {
  // Singleton instance (optional)
  static final PopularTracksManager _instance = PopularTracksManager._internal();
  factory PopularTracksManager() => _instance;
  PopularTracksManager._internal();

  // Internal list of popular tracks
  List<Map<String, dynamic>> _popularTracks = [];

  // Expose read-only list
  List<Map<String, dynamic>> get popularTracks => List.unmodifiable(_popularTracks);

  // For simplicity, an async init or refresh method
  Future<void> loadPopularTracks() async {
    // For now, mock data or empty list
    _popularTracks = [
      {'id': 'mock1', 'title': 'Mock Popular Song 1', 'artist': 'Artist A'},
      {'id': 'mock2', 'title': 'Mock Popular Song 2', 'artist': 'Artist B'},
    ];
    // Later: replace this with swarm data logic
  }

  // Method to update popular tracks based on swarm data later
  void updateFromSwarm(List<Map<String, dynamic>> swarmData) {
    _popularTracks = swarmData;
    // Possibly notify listeners if you use state management
  }
}


class BrowseScreen extends StatefulWidget {
  const BrowseScreen({Key? key}) : super(key: key);

  @override
  _BrowseScreenState createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PopularTracksManager popularTracksManager = PopularTracksManager();

  bool isLoadingPopular = false;

  @override
  void initState() {
    super.initState();
    _loadPopular();
  }

  Future<void> _loadPopular() async {
    setState(() => isLoadingPopular = true);
    await popularTracksManager.loadPopularTracks();
    setState(() => isLoadingPopular = false);
  }

  bool showAdvancedFilters = false;
  bool showRequestedOnly = false;

  // Advanced filters
  String artistFilter = '';
  String albumFilter = '';
  String yearFilter = '';

  List<dynamic> musicBrainzResults = [];
  List<dynamic> requestedSongs = [];

  bool isLoading = false;

  // Dummy seed counts for demo, replace with your real data
  Map<String, int> swarmSeedCounts = {};
  Map<String, int> localSeedCounts = {};

  String sortOption = 'Relevance'; // default

  String _sortOptionToString(SortOption option) {
    switch (option) {
      case SortOption.popularity:
        return 'Popularity';
      case SortOption.seedCount:
        return 'Seed Count';
      case SortOption.releaseCount:
        return 'Release Count';
      case SortOption.titleAsc:
        return 'Title (A-Z)';
      case SortOption.titleDesc:
        return 'Title (Z-A)';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Builds the MusicBrainz search query with advanced filters applied
  String buildMusicBrainzQuery(String searchTerm) {
    final buffer = StringBuffer();

    if (searchTerm.isNotEmpty) {
      buffer.write('recording:"$searchTerm"');
    }
    if (artistFilter.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' AND ');
      buffer.write('artist:"$artistFilter"');
    }
    if (albumFilter.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' AND ');
      buffer.write('release:"$albumFilter"');
    }
    if (yearFilter.isNotEmpty) {
      final rangeMatch = RegExp(r'^(\d{4})-(\d{4})$');
      final singleYearMatch = RegExp(r'^\d{4}$');

      if (rangeMatch.hasMatch(yearFilter)) {
        final match = rangeMatch.firstMatch(yearFilter);
        final start = match?.group(1);
        final end = match?.group(2);
        if (start != null && end != null) {
          if (buffer.isNotEmpty) buffer.write(' AND ');
          buffer.write('date:[$start TO $end]');
        }
      } else if (singleYearMatch.hasMatch(yearFilter)) {
        if (buffer.isNotEmpty) buffer.write(' AND ');
        buffer.write('date:$yearFilter');
      }
      // Otherwise ignore invalid format silently
    }

    return buffer.toString();
  }

  Future<void> searchMusicBrainz() async {
    final term = _searchController.text.trim();
    if (term.isEmpty && artistFilter.isEmpty && albumFilter.isEmpty &&
        yearFilter.isEmpty) {
      setState(() {
        musicBrainzResults = [];
      });
      return;
    }

    setState(() {
      isLoading = true;
      musicBrainzResults = [];
    });

    try {
      final query = buildMusicBrainzQuery(term);
      final encodedQuery = Uri.encodeQueryComponent(query);
      final url = 'https://musicbrainz.org/ws/2/recording?query=$encodedQuery&fmt=json&limit=50&inc=releases';

      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'AudynApp/1.0 (you@example.com)',
        // Replace with real email/app info
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonData = json.decode(response.body);
        final List<dynamic> recordings = jsonData['recordings'] ?? [];

        final enrichedResults = recordings.map((recording) {
          final releases = recording['releases'] ?? [];
          final releaseId = releases.isNotEmpty ? releases[0]['id'] : null;
          final releaseDate = releases.isNotEmpty
              ? releases[0]['date'] ?? ''
              : '';
          final duration = recording['length'] ?? 0;
          final id = recording['id'];

          return {
            'id': id,
            'title': recording['title'],
            'artist': recording['artist-credit']?[0]?['name'] ?? '',
            'coverUrl': releaseId != null
                ? 'https://coverartarchive.org/release/$releaseId/front-250'
                : null,
            'releaseDate': releaseDate,
            'releaseYear': releaseDate.length >= 4 ? int.tryParse(
                releaseDate.substring(0, 4)) : null,
            'releaseCount': releases.length,
            'length': duration,
            'releases': releases,
            'swarmSeeds': swarmSeedCounts[id] ?? 0,
            'localSeeds': localSeedCounts[id] ?? 0,
          };
        }).toList();

        // 🔀 Advanced Sorting Logic
        enrichedResults.sort((a, b) {
          switch (sortOption) {
            case 'Title A-Z':
              return (a['title'] ?? '').toLowerCase().compareTo(
                  (b['title'] ?? '').toLowerCase());
            case 'Title Z-A':
              return (b['title'] ?? '').toLowerCase().compareTo(
                  (a['title'] ?? '').toLowerCase());
            case 'Artist A-Z':
              return (a['artist'] ?? '').toLowerCase().compareTo(
                  (b['artist'] ?? '').toLowerCase());
            case 'Artist Z-A':
              return (b['artist'] ?? '').toLowerCase().compareTo(
                  (a['artist'] ?? '').toLowerCase());
            case 'Year Newest':
              return (b['releaseYear'] ?? 0).compareTo(a['releaseYear'] ?? 0);
            case 'Year Oldest':
              return (a['releaseYear'] ?? 9999).compareTo(
                  b['releaseYear'] ?? 9999);
            case 'Duration Longest':
              return (b['length'] ?? 0).compareTo(a['length'] ?? 0);
            case 'Duration Shortest':
              return (a['length'] ?? 0).compareTo(b['length'] ?? 0);
            case 'Most Swarm Seeds':
              return (b['swarmSeeds'] ?? 0).compareTo(a['swarmSeeds'] ?? 0);
            case 'Most Local Seeds':
              return (b['localSeeds'] ?? 0).compareTo(a['localSeeds'] ?? 0);
            default: // 'Relevance' or fallback
              return (b['releaseCount'] ?? 0).compareTo(a['releaseCount'] ?? 0);
          }
        });

        setState(() {
          musicBrainzResults = enrichedResults;
        });
      } else {
        print('MusicBrainz API error: ${response.statusCode}');
      }
    } catch (e) {
      print('MusicBrainz API exception: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }


  bool isAvailableInSwarm(String id) {
    final seeds = swarmSeedCounts[id] ?? 0;
    final local = localSeedCounts[id] ?? 0;
    return (seeds + local) > 0;
  }

  String? getCoverArtUrl(dynamic recording) {
    final releases = recording['releases'] as List<dynamic>? ?? [];
    if (releases.isNotEmpty && releases[0]['id'] != null) {
      final releaseId = releases[0]['id'];
      return 'https://coverartarchive.org/release/$releaseId/front-250';
    }
    return null;
  }

  List<String> selectedSortOptions = ['Relevance'];

  String? selectedTagFilter;
  String? selectedRatingFilter;
  String? selectedDurationFilter;

  bool nsfwFilter = false;

  final List<String> tagFilterOptions = [
    'Pop',
    'Rock',
    'Jazz',
    'Electronic',
    'Classical'
  ];
  final List<String> ratingFilterOptions = [
    '1 Star',
    '2 Stars',
    '3 Stars',
    '4 Stars',
    '5 Stars'
  ];
  final List<String> durationFilterOptions = [
    '< 3 min',
    '3-5 min',
    '5-10 min',
    '> 10 min'
  ];

  List<Map<String, dynamic>> popularTracks = [
    {
      'id': 'track1',
      'title': 'Echoes of Dawn',
      'artist': 'Solar Drift',
      'duration': 245, // seconds
      'year': 2023,
      'tags': ['ambient', 'chill'],
      'seeds': 120,
    },
    {
      'id': 'track2',
      'title': 'Neon Skyline',
      'artist': 'Night Pulse',
      'duration': 198,
      'year': 2024,
      'tags': ['synthwave', 'electronic'],
      'seeds': 87,
    },
    {
      'id': 'track3',
      'title': 'Gravity Falls',
      'artist': 'Zero Vector',
      'duration': 312,
      'year': 2022,
      'tags': ['instrumental', 'post-rock'],
      'seeds': 150,
    },
    {
      'id': 'track4',
      'title': 'Lunar Tide',
      'artist': 'Celeste Waves',
      'duration': 275,
      'year': 2023,
      'tags': ['ambient', 'electronic'],
      'seeds': 95,
    },
    {
      'id': 'track5',
      'title': 'Crimson Horizon',
      'artist': 'Blood Moon',
      'duration': 230,
      'year': 2021,
      'tags': ['rock', 'alternative'],
      'seeds': 110,
    },
  ];

// populate this from swarm / torrent data later

  Widget buildSearchFilters() {
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tag Filter Section
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4),
                child: Text(
                  "Tag Filter",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.builder(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: tagFilterOptions.length,
                  itemBuilder: (context, index) {
                    final tag = tagFilterOptions[index];
                    final selected = selectedTagFilter == tag;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            selectedTagFilter = selected ? null : tag;
                          });
                        },
                        selectedColor: Colors.lightBlueAccent,
                        backgroundColor: Colors.grey[800],
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Sort Options Section (Checkbox Chips)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4),
                child: Text(
                  "Sort Options",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final opt in [
                    'Relevance',
                    'Title A-Z',
                    'Title Z-A',
                    'Artist A-Z',
                    'Artist Z-A',
                    'Year Newest',
                    'Year Oldest',
                    'Duration Longest',
                    'Duration Shortest',
                    'Most Swarm Seeds',
                    'Most Local Seeds',
                  ])
                    FilterChip(
                      label: Text(
                          opt, style: const TextStyle(color: Colors.white)),
                      selected: selectedSortOptions.contains(opt),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedSortOptions.add(opt);
                          } else {
                            selectedSortOptions.remove(opt);
                          }
                        });
                      },
                      selectedColor: Colors.lightBlueAccent,
                      backgroundColor: Colors.grey[800],
                      checkmarkColor: Colors.black,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Rating Filter Section
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4),
                child: Text(
                  "Rating Filter",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.builder(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: ratingFilterOptions.length,
                  itemBuilder: (context, index) {
                    final rating = ratingFilterOptions[index];
                    final selected = selectedRatingFilter == rating;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(rating),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            selectedRatingFilter = selected ? null : rating;
                          });
                        },
                        selectedColor: Colors.lightBlueAccent,
                        backgroundColor: Colors.grey[800],
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Duration Filter Section
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 4),
                child: Text(
                  "Duration Filter",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.builder(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: durationFilterOptions.length,
                  itemBuilder: (context, index) {
                    final dur = durationFilterOptions[index];
                    final selected = selectedDurationFilter == dur;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(dur),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            selectedDurationFilter = selected ? null : dur;
                          });
                        },
                        selectedColor: Colors.lightBlueAccent,
                        backgroundColor: Colors.grey[800],
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // NSFW Filter Toggle
              Row(
                children: [
                  Checkbox(
                    value: nsfwFilter,
                    onChanged: (v) {
                      setState(() {
                        nsfwFilter = v ?? false;
                      });
                    },
                    fillColor: MaterialStateProperty.all(
                        Colors.lightBlueAccent),
                  ),
                  const Text(
                    "Allow NSFW",
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),

              // Search Button
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton(
                  onPressed: () {
                    searchMusicBrainz();
                  },
                  child: const Text("Search"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Sorting logic function example inside searchMusicBrainz or similar
  void applySorting(List<Map<String, dynamic>> results) {
    // Sort with multi-criteria, last selected priority applied first
    for (final opt in selectedSortOptions.reversed) {
      results.sort((a, b) {
        switch (opt) {
          case 'Title A-Z':
            return (a['title'] ?? '').toLowerCase().compareTo(
                (b['title'] ?? '').toLowerCase());
          case 'Title Z-A':
            return (b['title'] ?? '').toLowerCase().compareTo(
                (a['title'] ?? '').toLowerCase());
          case 'Artist A-Z':
            return (a['artist'] ?? '').toLowerCase().compareTo(
                (b['artist'] ?? '').toLowerCase());
          case 'Artist Z-A':
            return (b['artist'] ?? '').toLowerCase().compareTo(
                (a['artist'] ?? '').toLowerCase());
          case 'Year Newest':
            return (b['releaseYear'] ?? 0).compareTo(a['releaseYear'] ?? 0);
          case 'Year Oldest':
            return (a['releaseYear'] ?? 9999).compareTo(
                b['releaseYear'] ?? 9999);
          case 'Duration Longest':
            return (b['length'] ?? 0).compareTo(a['length'] ?? 0);
          case 'Duration Shortest':
            return (a['length'] ?? 0).compareTo(b['length'] ?? 0);
          case 'Most Swarm Seeds':
            return (b['swarmSeeds'] ?? 0).compareTo(a['swarmSeeds'] ?? 0);
          case 'Most Local Seeds':
            return (b['localSeeds'] ?? 0).compareTo(a['localSeeds'] ?? 0);
          case 'Relevance':
          default:
            return (b['releaseCount'] ?? 0).compareTo(a['releaseCount'] ?? 0);
        }
      });
    }
  }

  Widget buildSongCard(dynamic recording) {
    final id = recording['id'] as String? ?? '';
    final title = recording['title'] as String? ?? 'Unknown title';

    final artistCredit = recording['artist-credit'] as List<dynamic>? ?? [];
    final artistName = artistCredit.isNotEmpty
        ? (artistCredit[0]['name'] as String? ?? 'Unknown artist')
        : 'Unknown artist';

    final available = isAvailableInSwarm(id);
    final coverUrl = getCoverArtUrl(recording);

    final swarmSeeds = swarmSeedCounts[id] ?? 0;
    final localSeeds = localSeedCounts[id] ?? 0;

    final isRequested = requestedSongs.any((r) =>
    (r['id'] as String? ?? '') == id);

    // Optional: Duration display
    final durationMs = recording['length'] as int?;
    final durationFormatted = durationMs != null
        ? '${(durationMs ~/ 60000).toString().padLeft(1, '0')}:${((durationMs %
        60000) ~/ 1000).toString().padLeft(2, '0')}'
        : null;

    // Optional: Release year
    final releaseDate = (recording['releases']?[0]?['date'] ?? '') as String;
    final releaseYear = releaseDate.isNotEmpty ? releaseDate
        .split('-')
        .first : null;

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: coverUrl != null
              ? Image.network(
            coverUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.album, size: 56, color: Colors.grey[700]),
          )
              : Icon(Icons.album, size: 56, color: Colors.grey[700]),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isRequested)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Requested',
                    style: TextStyle(color: Colors.black, fontSize: 10)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$artistName${releaseYear != null ? ' • $releaseYear' : ''}',
                style: TextStyle(color: Colors.grey[400])),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.cloud, size: 14, color: Colors.lightBlueAccent),
                SizedBox(width: 4),
                Text('$swarmSeeds seeds',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                SizedBox(width: 12),
                Icon(Icons.hub, size: 14, color: Colors.lightBlueAccent),
                SizedBox(width: 4),
                Text('$localSeeds local',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                if (durationFormatted != null) ...[
                  SizedBox(width: 12),
                  Icon(Icons.access_time, size: 14, color: Colors.white30),
                  SizedBox(width: 4),
                  Text(durationFormatted,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ],
            ),
          ],
        ),
        trailing: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 0, maxWidth: 90),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              backgroundColor: isRequested
                  ? Colors.orangeAccent
                  : (available ? Colors.lightBlueAccent : Colors.transparent),
              side: !available && !isRequested
                  ? BorderSide(color: Colors.lightBlueAccent!)
                  : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              minimumSize: Size(0, 36),
              // Shrinks button height
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              setState(() {
                if (isRequested) {
                  requestedSongs.removeWhere((r) =>
                  (r['id'] as String? ?? '') == id);
                } else {
                  requestedSongs.add(recording);
                }
              });
            },
            child: Text(
              isRequested ? 'Requested' : (available ? 'Play' : 'Request'),
              style: TextStyle(
                fontSize: 12,
                color: isRequested
                    ? Colors.black
                    : (available ? Colors.black : Colors.lightBlueAccent),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.trim();

    // Show popular tracks when search bar is empty, else show filtered results
    final displayedResults = searchQuery.isEmpty
        ? popularTracks
        : (showRequestedOnly
        ? musicBrainzResults.where((rec) {
      final id = rec['id'] as String? ?? '';
      return requestedSongs.any((r) => (r['id'] as String? ?? '') == id);
    }).toList()
        : musicBrainzResults);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Browse Songs'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search input
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by song title...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                hintStyle: const TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  // Refresh UI on input change
                });
              },
              onSubmitted: (_) => searchMusicBrainz(),
            ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    showAdvancedFilters = !showAdvancedFilters;
                  });
                },
                icon: Icon(
                  showAdvancedFilters ? Icons.filter_alt_off : Icons.filter_alt,
                  color: Colors.lightBlueAccent,
                ),
                label: Text(
                  showAdvancedFilters ? 'Hide Filters' : 'Show Filters',
                  style: TextStyle(color: Colors.lightBlueAccent),
                ),
              ),
            ),

            if (showAdvancedFilters)
              SafeArea(
                child: SizedBox(
                  height: 200, // fixed height to avoid overflow
                  child: buildSearchFilters(),
                ),
              ),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(color: Colors.lightBlueAccent),
              ),

            const SizedBox(height: 12),

            Expanded(
              child: displayedResults.isEmpty
                  ? Center(
                child: Text(
                  searchQuery.isEmpty
                      ? 'No popular tracks available'
                      : (showRequestedOnly
                      ? 'No requested songs found'
                      : 'No results found'),
                  style: TextStyle(color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              )
                  : ListView.builder(
                itemCount: displayedResults.length,
                itemBuilder: (context, index) {
                  final recording = displayedResults[index];
                  return buildSongCard(recording);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}