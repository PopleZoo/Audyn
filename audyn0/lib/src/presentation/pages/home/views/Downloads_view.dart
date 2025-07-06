import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../bloc/Downloads/DownloadsBloc.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'completed': return cs.secondary;
      case 'downloading': return cs.primary;
      case 'failed': return cs.error;
      default: return cs.outline;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed': return Icons.check_circle;
      case 'downloading': return Icons.downloading;
      case 'failed': return Icons.error;
      default: return Icons.help_outline;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'completed': return 'Completed';
      case 'downloading': return 'Downloading…';
      case 'failed': return 'Failed';
      default: return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        elevation: 1,
      ),
      body: BlocBuilder<DownloadsBloc, DownloadsState>(
        builder: (context, state) {
          if (state.downloads.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_for_offline, size: 64, color: cs.onBackground.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No downloads found.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: cs.onBackground.withOpacity(0.6)),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            itemCount: state.downloads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = state.downloads[index];

              final title = (track.title?.isNotEmpty ?? false) ? track.title! : track.name;
              final artist = track.artist ?? 'Unknown Artist';
              final album = track.album ?? '';
              final status = track.status;
              final progress = (track.progress ?? 0).clamp(0.0, 1.0);
              final folder = track.filePath ?? '';
              final art = track.albumArt;

              return Material(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {}, // Future: open or play
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status sticker
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 12, top: 2),
                          decoration: BoxDecoration(
                            color: _statusColor(context, status),
                            shape: BoxShape.circle,
                          ),
                        ),

                        // Album art or fallback icon
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: art != null
                              ? Image.memory(art, width: 56, height: 56, fit: BoxFit.cover)
                              : Container(
                            width: 56,
                            height: 56,
                            color: cs.surfaceVariant,
                            child: const Icon(Icons.music_note, size: 32),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Metadata & progress
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                album.isNotEmpty ? '$artist • $album' : artist,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.6),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
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
                                ],
                              ),
                              if (status == 'downloading') ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: theme.dividerColor,
                                    valueColor: AlwaysStoppedAnimation<Color>(_statusColor(context, status)),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                folder,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.4),
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
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
