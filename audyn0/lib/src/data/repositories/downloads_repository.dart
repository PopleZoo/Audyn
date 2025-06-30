import 'package:audyn/src/data/models/Download_Item.dart';

class DownloadsRepository {
  // In-memory list of downloads (replace with actual storage/db)
  final List<DownloadItem> _downloads = [];

  // Get all downloads
  List<DownloadItem> getAllDownloads() {
    return List.unmodifiable(_downloads);
  }

  // Add a new download
  void addDownload(DownloadItem item) {
    _downloads.add(item);
  }

  // Remove a download by infoHash or unique ID
  void removeDownload(String infoHash) {
    _downloads.removeWhere((item) => item.infoHash == infoHash);
  }

  // Update a download (find by infoHash)
  void updateDownload(DownloadItem updatedItem) {
    final index = _downloads.indexWhere((item) => item.infoHash == updatedItem.infoHash);
    if (index != -1) {
      _downloads[index] = updatedItem;
    }
  }

  // Find a download by infoHash
  DownloadItem? getDownload(String infoHash) {
    try {
      return _downloads.firstWhere((item) => item.infoHash == infoHash);
    } catch (_) {
      return null;
    }
  }
}
