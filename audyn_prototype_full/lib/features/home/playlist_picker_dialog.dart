import 'package:flutter/material.dart';
import '../../core/models/playlist.dart';

class PlaylistPickerDialog extends StatefulWidget {
  final List<Playlist> playlists;

  const PlaylistPickerDialog({super.key, required this.playlists});

  @override
  State<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
}

class _PlaylistPickerDialogState extends State<PlaylistPickerDialog> {
  String? _newPlaylistName;
  TextEditingController? _newPlaylistController;

  @override
  void initState() {
    super.initState();
    _newPlaylistController = TextEditingController();
  }

  @override
  void dispose() {
    _newPlaylistController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select or create a playlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // List existing playlists
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = widget.playlists[index];
                  return ListTile(
                    title: Text(playlist.name),
                    onTap: () => Navigator.pop(context, playlist.id),
                  );
                },
              ),
            ),
            const Divider(),
            // Create new playlist
            TextField(
              controller: _newPlaylistController,
              decoration: InputDecoration(
                labelText: 'New playlist name',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    final name = _newPlaylistController!.text.trim();
                    if (name.isNotEmpty) {
                      Navigator.pop(context, 'new:$name');
                    }
                  },
                ),
              ),
              onSubmitted: (value) {
                final name = value.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context, 'new:$name');
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
