import 'package:flutter_test/flutter_test.dart';
import 'package:mbx_app/models/media_models.dart';

void main() {
  test('Episode navigation calculation test', () {
    final seasons = [
      SeasonItem(seasonNumber: 1, title: 'Season 1', episodeCount: 3),
      SeasonItem(seasonNumber: 2, title: 'Season 2', episodeCount: 2),
    ];
    final episodes = [
      EpisodeItem(episodeNumber: 1, seasonNumber: 1, title: 'Pilot'),
      EpisodeItem(episodeNumber: 2, seasonNumber: 1, title: 'Episode 2'),
      EpisodeItem(episodeNumber: 3, seasonNumber: 1, title: 'Episode 3'),
    ];

    // Case 1: Within same season
    int currentEpisode = 1;
    final currIdx = episodes.indexWhere((e) => e.episodeNumber == currentEpisode);
    expect(currIdx, equals(0));
    expect(episodes[currIdx + 1].episodeNumber, equals(2));

    // Case 2: Last episode of season -> transitions to season 2
    currentEpisode = 3;
    final lastIdx = episodes.indexWhere((e) => e.episodeNumber == currentEpisode);
    final hasNextInSeason = lastIdx != -1 && lastIdx + 1 < episodes.length;
    expect(hasNextInSeason, isFalse);

    final nextSeason = seasons.where((s) => s.seasonNumber > 1).firstOrNull;
    expect(nextSeason?.seasonNumber, equals(2));
  });
}
