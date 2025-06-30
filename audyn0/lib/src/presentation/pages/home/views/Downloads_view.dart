import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../bloc/Downloads/DownloadsBloc.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  // Returns the color for different download statuses
  Color _statusColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'completed':
        return colorScheme.secondary;
      case 'downloading':
        return colorScheme.primary;
      case 'failed':
        return colorScheme.error;
      default:
        return colorScheme.onBackground.withOpacity(0.6);
    }
  }

  // Returns icon for the status
  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'downloading':
        return Icons.downloading;
      case 'failed':
        return Icons.error;
      default:
        return Icons.help_outline;
    }
  }

  // Returns text label for the status
  String _statusText(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'downloading':
        return 'Downloading...';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: BlocBuilder<DownloadsBloc, DownloadsState>(
        builder: (context, state) {
          if (state.downloads.isEmpty) {
            // Show empty state UI
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.download_for_offline,
                    size: 64,
                    color: colorScheme.onBackground.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No downloads found.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onBackground.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            );
          }

          // Show list of downloads
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: state.downloads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = state.downloads[index];

              final String title = (track.title?.isNotEmpty ?? false) ? track.title! : track.name;
              final String artist = track.artist ?? 'Unknown Artist';
              final String album = track.album ?? '';
              final String status = track.status;
              final double progress = (track.progress ?? 0).clamp(0.0, 1.0);
              final String fileSize = '—'; // TODO: Implement file size display
              final String duration = '';   // TODO: Implement duration display
              final String destinationFolder = track.filePath ?? '';
              final Uint8List? albumArt = track.albumArt;

              return Material(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (status == 'completed') {
                      // TODO: Implement playback
                    } else if (status == 'failed') {
                      // TODO: Implement retry logic
                    }
                  },
                  onLongPress: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => SafeArea(
                        child: ListTile(
                          leading: const Icon(Icons.delete),
                          title: const Text('Delete Download'),
                          onTap: () {
                            context.read<DownloadsBloc>().add(DeleteDownload(track.infoHash));
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: albumArt != null
                              ? Image.memory(albumArt, width: 56, height: 56, fit: BoxFit.cover)
                              : Container(
                            width: 56,
                            height: 56,
                            color: colorScheme.surfaceVariant,
                            child: const Icon(Icons.music_note, color: Colors.white70, size: 36),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: theme.textTheme.titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (duration.isNotEmpty)
                                    Text(
                                      duration,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                album.isNotEmpty ? '$artist • $album' : artist,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(_statusIcon(status), size: 16, color: _statusColor(context, status)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _statusText(status),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: _statusColor(context, status),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        fileSize,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onSurface.withOpacity(0.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (status == 'downloading')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          minHeight: 5,
                                          backgroundColor: theme.dividerColor,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            _statusColor(context, status),
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    destinationFolder,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(0.3),
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
