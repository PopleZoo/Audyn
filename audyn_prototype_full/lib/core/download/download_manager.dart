import 'package:flutter/foundation.dart';

class DownloadTask {
  final String id;
  final String title;
  final String magnetLink; // or .torrent file path
  final String savePath;

  int totalSize; // bytes (can be 0 if unknown)
  int downloadedBytes; // current downloaded bytes
  int seeds;
  int peers;
  bool isSeeding;

  double progress; // 0.0 to 1.0
  bool isComplete;
  bool isError;
  String? errorMessage;

  DownloadTask({
    required this.id,
    required this.title,
    required this.magnetLink,
    required this.savePath,
    this.totalSize = 0,
    this.downloadedBytes = 0,
    this.seeds = 0,
    this.peers = 0,
    this.isSeeding = false,
    this.progress = 0.0,
    this.isComplete = false,
    this.isError = false,
    this.errorMessage,
  });

  double get computedProgress {
    if (totalSize == 0) return progress; // fallback to reported progress
    return downloadedBytes / totalSize;
  }
}
class DownloadManager extends ChangeNotifier {
  final List<DownloadTask> _downloads = [];

  List<DownloadTask> get activeDownloads =>
      _downloads.where((task) => !task.isComplete).toList();

  List<DownloadTask> get completedDownloads =>
      _downloads.where((task) => task.isComplete).toList();

  double get overallProgress {
    if (_downloads.isEmpty) return 0.0;
    final total = _downloads.fold<double>(0, (sum, task) => sum + task.computedProgress);
    return total / _downloads.length;
  }

  void addDownload({
    required String title,
    required String magnetLink,
    required String savePath,
  }) {
    final task = DownloadTask(
      id: UniqueKey().toString(),
      title: title,
      magnetLink: magnetLink,
      savePath: savePath,
    );
    _downloads.add(task);
    notifyListeners();

    _startDownload(task); // Placeholder for actual implementation
  }

  void _startDownload(DownloadTask task) async {
    // Replace this with actual API/torrent client logic
    try {
      for (int i = 1; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        task.progress = i / 10;
        // simulate seeds and peers increasing:
        task.seeds = i * 2;
        task.peers = i * 3;
        task.downloadedBytes = (task.totalSize * task.progress).toInt();
        notifyListeners();
      }

      task.isComplete = true;
      task.isSeeding = true; // Automatically start seeding after complete
      notifyListeners();
    } catch (e) {
      task.isError = true;
      task.errorMessage = e.toString();
      notifyListeners();
    }
  }

  void removeDownload(String id) {
    _downloads.removeWhere((task) => task.id == id);
    notifyListeners();
  }

  void clearCompleted() {
    _downloads.removeWhere((task) => task.isComplete);
    notifyListeners();
  }

  void reset() {
    _downloads.clear();
    notifyListeners();
  }

  void updateProgress(String id, {
    int? downloadedBytes,
    int? totalSize,
    int? seeds,
    int? peers,
    bool? isSeeding,
    double? progress,
    bool? isComplete,
    bool? isError,
    String? errorMessage,
  }) {
    final task = _downloads.firstWhere((d) => d.id == id, orElse: () => throw Exception('Download not found'));

    if (downloadedBytes != null) task.downloadedBytes = downloadedBytes;
    if (totalSize != null) task.totalSize = totalSize;
    if (seeds != null) task.seeds = seeds;
    if (peers != null) task.peers = peers;
    if (isSeeding != null) task.isSeeding = isSeeding;
    if (progress != null) task.progress = progress;
    if (isComplete != null) task.isComplete = isComplete;
    if (isError != null) task.isError = isError;
    if (errorMessage != null) task.errorMessage = errorMessage;

    notifyListeners();
  }
}
