import 'package:flutter/foundation.dart';
import '../models/media_models.dart';
import '../services/download_service.dart';

/// Middleman Coordinator bridging UI download buttons/screens with the DownloadService backend.
class DownloadCoordinator extends ChangeNotifier {
  static final DownloadCoordinator instance = DownloadCoordinator._();
  DownloadCoordinator._();

  final DownloadService _service = DownloadService.instance;

  List<DownloadTask> get tasks => _service.tasks;

  DownloadService get service => _service;

  String generateTaskId({
    required String subjectId,
    int season = 0,
    int episode = 0,
    required String resolution,
  }) {
    return "${subjectId}_${season}_${episode}_$resolution";
  }

  String formatDownloadTitle({
    required String title,
    String? episodeTitle,
    int season = 0,
    int episode = 0,
  }) {
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      return "$title - $episodeTitle";
    }
    if (season > 0 && episode > 0) {
      return "$title - S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}";
    }
    return title;
  }

  String determineExtension(StreamOption stream) {
    if (stream.kind == 'dash' || stream.url.contains('.mpd')) {
      return 'mpd';
    }
    if (stream.kind == 'hls' || stream.url.contains('.m3u8')) {
      return 'm3u8';
    }
    return 'mp4';
  }

  bool isMediaDownloadingOrCompleted(String subjectId) {
    return _service.tasks.any(
      (t) => t.id.startsWith("${subjectId}_") && !t.isCancelled && !t.status.startsWith("Failed"),
    );
  }

  Future<void> requestDownload({
    required String subjectId,
    required String title,
    required StreamOption stream,
    int season = 0,
    int episode = 0,
    String? episodeTitle,
  }) async {
    final taskId = generateTaskId(
      subjectId: subjectId,
      season: season,
      episode: episode,
      resolution: stream.resolution,
    );

    final formattedTitle = formatDownloadTitle(
      title: title,
      episodeTitle: episodeTitle,
      season: season,
      episode: episode,
    );

    final ext = determineExtension(stream);

    await _service.startDownload(
      id: taskId,
      title: formattedTitle,
      url: stream.url,
      cookie: stream.cookie,
      ext: ext,
    );
    notifyListeners();
  }

  void cancelDownload(String taskId) {
    _service.cancelDownload(taskId);
    notifyListeners();
  }

  Future<void> deleteDownload(String taskId) async {
    await _service.deleteDownload(taskId);
    notifyListeners();
  }
}
