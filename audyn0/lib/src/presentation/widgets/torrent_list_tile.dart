import 'package:flutter/material.dart';

/// A single torrent item tile, showing album art, title, artist, album,
/// and handling selection and tap/long press.
/// This assumes you pass in a torrent Map<String, dynamic> with keys:
///   - 'title' (String)
///   - 'artist' (String)
///   - 'album' (String)
///   - 'art_url' (String, nullable)
///   - 'info_hash' (String)
///   - 'isSelected' (bool)
///   - optional callbacks onTap, onLongPress
class TorrentListTile extends StatelessWidget {
  final Map<String, dynamic> torrent;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TorrentListTile({
    Key? key,
    required this.torrent,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String title = torrent['title'] ?? torrent['name'] ?? 'Unknown';
    final String artist = torrent['artist'] ?? 'Unknown';
    final String album = torrent['album'] ?? 'Unknown';
    final String? artUrl = torrent['art_url'];
    final bool hasArt = artUrl != null && artUrl.isNotEmpty;

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.secondary.withOpacity(0.2),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: hasArt
          ? ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          artUrl!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultIcon(theme),
        ),
      )
          : _defaultIcon(theme),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.textTheme.bodyLarge?.color,
        ),
      ),
      subtitle: Text(
        '$artist | $album',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
        ),
      ),
      trailing: _buildTrailingIcon(torrent, theme),
    );
  }

  Widget _defaultIcon(ThemeData theme) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.music_note_outlined,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildTrailingIcon(Map<String, dynamic> torrent, ThemeData theme) {
    // You can customize this to show seeding status or upload/download icons
    final bool isSeeding = torrent['state'] == 5 || torrent['seed_mode'] == true;
    final bool isLocal = (torrent['vault_files'] as List?)?.isNotEmpty ?? false;

    if (isLocal) {
      return Icon(Icons.check_circle, color: theme.colorScheme.secondary);
    } else if (isSeeding) {
      return Icon(Icons.cloud_upload, color: theme.colorScheme.primary);
    } else {
      return Icon(Icons.cloud_download, color: Colors.grey.shade400);
    }
  }
}
