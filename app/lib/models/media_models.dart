class MediaItem {
  final String id;
  final String title;
  final String? poster;
  final String? year;
  final String? rating;
  final String? description;
  final int? type; // 1 = Movie, 2 = Series

  MediaItem({
    required this.id,
    required this.title,
    this.poster,
    this.year,
    this.rating,
    this.description,
    this.type,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    String? posterUrl;
    final cover = json['cover'] ?? json['poster'] ?? json['imageUrl'] ?? json['verticalUrl'];
    if (cover is Map) {
      posterUrl = cover['url'] ?? cover['imageUrl'];
    } else if (cover != null) {
      posterUrl = cover.toString();
    }

    final yearVal = json['year'] ?? json['releaseYear'] ?? json['releaseDate'];
    final yearStr = yearVal != null ? yearVal.toString().substring(0, yearVal.toString().length >= 4 ? 4 : null) : null;
    final ratingVal = json['score'] ?? json['rating'] ?? json['imdbScore'];

    return MediaItem(
      id: (json['id'] ?? json['subjectId'] ?? '').toString(),
      title: (json['title'] ?? json['subjectName'] ?? json['name'] ?? 'Unknown').toString(),
      poster: posterUrl,
      year: yearStr,
      rating: ratingVal?.toString(),
      description: (json['description'] ?? json['synopsis'] ?? json['desc'] ?? '').toString(),
      type: json['subjectType'] as int? ?? json['type'] as int?,
    );
  }
}

class SeasonItem {
  final int seasonNumber;
  final String title;
  final int episodeCount;

  SeasonItem({
    required this.seasonNumber,
    required this.title,
    required this.episodeCount,
  });
}

class EpisodeItem {
  final int episodeNumber;
  final int seasonNumber;
  final String title;
  final String? description;

  EpisodeItem({
    required this.episodeNumber,
    required this.seasonNumber,
    required this.title,
    this.description,
  });
}

class StreamOption {
  final String url;
  final String kind; // 'hls' or 'dash' or 'mp4'
  final String resolution;
  final double? sizeMb;
  final int? durationSeconds;
  final String? cookie;
  final bool bypassedDecoy;

  StreamOption({
    required this.url,
    required this.kind,
    required this.resolution,
    this.sizeMb,
    this.durationSeconds,
    this.cookie,
    this.bypassedDecoy = false,
  });
}

class DownloadTask {
  final String id;
  final String title;
  final String filePath;
  double progress;
  bool isCompleted;
  String status;

  DownloadTask({
    required this.id,
    required this.title,
    required this.filePath,
    this.progress = 0.0,
    this.isCompleted = false,
    this.status = 'Downloading',
  });
}
