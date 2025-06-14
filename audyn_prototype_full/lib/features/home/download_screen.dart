import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/download/download_manager.dart';

class DownloadScreen extends StatelessWidget {
  const DownloadScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final downloadManager = context.watch<DownloadManager>();

    final downloads = [
      ...downloadManager.activeDownloads,
      // Add test tile manually
      DownloadTask(
        id: 'test-id',
        title: 'Test Track - Downloading',
        magnetLink: '',
        savePath: '',
        progress: 0.42,
        isComplete: false,
        isSeeding: true,
        seeds: 12,
        peers: 9,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Spotify dark background
      appBar: AppBar(
        title: const Text('Downloads'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: downloads.length,
        itemBuilder: (context, index) {
          final download = downloads[index];
          final progressPercent = (download.progress * 100).toStringAsFixed(1);

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 16),
              title: Text(
                download.title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: download.progress,
                    backgroundColor: Colors.grey.shade800,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress: $progressPercent%',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        'Seeds: ${download.seeds}  Peers: ${download.peers}',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                  if (download.isSeeding)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Seeding',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
