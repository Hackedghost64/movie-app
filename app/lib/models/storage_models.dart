import 'media_models.dart';

class WatchProgress {
  final String subjectId;
  final String title;
  final String? poster;
  final int season;
  final int episode;
  final String? episodeTitle;
  final int positionMs;
  final int durationMs;
  final int lastWatchedMs;
  final String? streamUrl;
  final String? streamCookie;

  WatchProgress({
    required this.subjectId,
    required this.title,
    this.poster,
    this.season = 0,
    this.episode = 0,
    this.episodeTitle,
    this.positionMs = 0,
    this.durationMs = 0,
    required this.lastWatchedMs,
    this.streamUrl,
    this.streamCookie,
  });

  double get progressPercentage =>
      durationMs > 0 ? positionMs / durationMs : 0.0;

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'title': title,
        'poster': poster,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lastWatchedMs': lastWatchedMs,
        'streamUrl': streamUrl,
        'streamCookie': streamCookie,
      };

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
        subjectId: (json['subjectId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        poster: json['poster'] as String?,
        season: (json['season'] as num?)?.toInt() ?? 0,
        episode: (json['episode'] as num?)?.toInt() ?? 0,
        episodeTitle: json['episodeTitle'] as String?,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        lastWatchedMs: (json['lastWatchedMs'] as num?)?.toInt() ?? 0,
        streamUrl: json['streamUrl'] as String?,
        streamCookie: json['streamCookie'] as String?,
      );

  WatchProgress copyWith({
    String? subjectId,
    String? title,
    String? poster,
    int? season,
    int? episode,
    String? episodeTitle,
    int? positionMs,
    int? durationMs,
    int? lastWatchedMs,
    String? streamUrl,
    String? streamCookie,
  }) {
    return WatchProgress(
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lastWatchedMs: lastWatchedMs ?? this.lastWatchedMs,
      streamUrl: streamUrl ?? this.streamUrl,
      streamCookie: streamCookie ?? this.streamCookie,
    );
  }
}

class WatchlistItem {
  final String id;
  final String title;
  final String? poster;
  final String? year;
  final String? rating;
  final int? type; // 1 = Movie, 2 = Series
  final int addedAtMs;

  WatchlistItem({
    required this.id,
    required this.title,
    this.poster,
    this.year,
    this.rating,
    this.type,
    required this.addedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster': poster,
        'year': year,
        'rating': rating,
        'type': type,
        'addedAtMs': addedAtMs,
      };

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        poster: json['poster'] as String?,
        year: json['year'] as String?,
        rating: json['rating'] as String?,
        type: (json['type'] as num?)?.toInt(),
        addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
      );

  factory WatchlistItem.fromMediaItem(MediaItem item, {int? addedAtMs}) =>
      WatchlistItem(
        id: item.id,
        title: item.title,
        poster: item.poster,
        year: item.year,
        rating: item.rating,
        type: item.type,
        addedAtMs: addedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        poster: poster,
        year: year,
        rating: rating,
        type: type,
      );
}
