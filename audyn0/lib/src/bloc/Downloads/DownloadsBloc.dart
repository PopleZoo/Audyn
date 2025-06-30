import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../data/models/Download_Item.dart';
import '../../data/repositories/downloads_repository.dart';

// Events
abstract class DownloadsEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadDownloads extends DownloadsEvent {}

class StartDownload extends DownloadsEvent {
  final String infoHash;
  final String name;

  StartDownload(this.infoHash, this.name);

  @override
  List<Object?> get props => [infoHash, name];
}

class UpdateDownloadProgress extends DownloadsEvent {
  final String infoHash;
  final double progress;

  UpdateDownloadProgress(this.infoHash, this.progress);

  @override
  List<Object?> get props => [infoHash, progress];
}

class CompleteDownload extends DownloadsEvent {
  final String infoHash;
  final String filePath;

  CompleteDownload(this.infoHash, this.filePath);

  @override
  List<Object?> get props => [infoHash, filePath];
}

class FailDownload extends DownloadsEvent {
  final String infoHash;

  FailDownload(this.infoHash);

  @override
  List<Object?> get props => [infoHash];
}

class DeleteDownload extends DownloadsEvent {
  final String infoHash;

  DeleteDownload(this.infoHash);

  @override
  List<Object?> get props => [infoHash];
}

// State
class DownloadsState extends Equatable {
  final List<DownloadItem> downloads;

  const DownloadsState({this.downloads = const []});

  DownloadsState copyWith({List<DownloadItem>? downloads}) {
    return DownloadsState(downloads: downloads ?? this.downloads);
  }

  @override
  List<Object?> get props => [downloads];
}

// Bloc
class DownloadsBloc extends Bloc<DownloadsEvent, DownloadsState> {
  final DownloadsRepository repository;

  DownloadsBloc({required this.repository}) : super(const DownloadsState()) {
    on<LoadDownloads>(_onLoadDownloads);
    on<StartDownload>(_onStartDownload);
    on<UpdateDownloadProgress>(_onUpdateDownloadProgress);
    on<CompleteDownload>(_onCompleteDownload);
    on<FailDownload>(_onFailDownload);
    on<DeleteDownload>(_onDeleteDownload);
  }

  Future<void> _onLoadDownloads(LoadDownloads event, Emitter<DownloadsState> emit) async {
    // TODO: Load persisted downloads from repository (e.g. Hive, DB)
    final loadedDownloads = await repository.getAllDownloads();
    emit(state.copyWith(downloads: loadedDownloads));
  }

  void _onStartDownload(StartDownload event, Emitter<DownloadsState> emit) {
    final existing = state.downloads.where((d) => d.infoHash == event.infoHash);
    if (existing.isEmpty) {
      final newDownload = DownloadItem(
        infoHash: event.infoHash,
        name: event.name,
        status: 'downloading',
        progress: 0.0,
      );
      final updatedList = List<DownloadItem>.from(state.downloads)..add(newDownload);
      emit(state.copyWith(downloads: updatedList));

      // TODO: Persist new download to repository
      repository.addDownload(newDownload);

      // TODO: Start actual download process (network request, torrent client, etc)
    }
  }

  void _onUpdateDownloadProgress(UpdateDownloadProgress event, Emitter<DownloadsState> emit) {
    final updated = state.downloads.map((d) {
      if (d.infoHash == event.infoHash) {
        final updatedDownload = d.copyWith(progress: event.progress);

        // TODO: Update download progress in repository if needed
        repository.updateDownload(updatedDownload);

        return updatedDownload;
      }
      return d;
    }).toList();
    emit(state.copyWith(downloads: updated));
  }

  void _onCompleteDownload(CompleteDownload event, Emitter<DownloadsState> emit) {
    final updated = state.downloads.map((d) {
      if (d.infoHash == event.infoHash) {
        final updatedDownload = d.copyWith(
          status: 'completed',
          progress: 1.0,
          filePath: event.filePath,
        );

        // TODO: Update completed download in repository
        repository.updateDownload(updatedDownload);

        return updatedDownload;
      }
      return d;
    }).toList();
    emit(state.copyWith(downloads: updated));

    // TODO: Optionally trigger playback or notification here
  }

  void _onFailDownload(FailDownload event, Emitter<DownloadsState> emit) {
    final updated = state.downloads.map((d) {
      if (d.infoHash == event.infoHash) {
        final updatedDownload = d.copyWith(
          status: 'failed',
          progress: 0.0,
        );

        // TODO: Update failed download in repository
        repository.updateDownload(updatedDownload);

        return updatedDownload;
      }
      return d;
    }).toList();
    emit(state.copyWith(downloads: updated));

    // TODO: Optionally trigger retry logic or user notification here
  }

  void _onDeleteDownload(DeleteDownload event, Emitter<DownloadsState> emit) {
    final filtered = state.downloads.where((d) => d.infoHash != event.infoHash).toList();
    emit(state.copyWith(downloads: filtered));

    // TODO: Delete download from repository and possibly delete file from storage
    repository.removeDownload(event.infoHash);
  }
}
