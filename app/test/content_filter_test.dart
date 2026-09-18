import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbx_app/models/media_models.dart';
import 'package:mbx_app/services/content_filter_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Content filter is ON by default', () async {
    final filter = ContentFilterService.instance;
    await filter.init();
    expect(filter.isFilterEnabled, isTrue);
  });

  test('Filters out adult keywords and platforms', () async {
    final filter = ContentFilterService.instance;
    await filter.init();

    final adultItems = [
      MediaItem(id: '1', title: 'Sensual Night 18+'),
      MediaItem(id: '2', title: 'Ullu Original Series'),
      MediaItem(id: '3', title: 'Hot Erotic Romance'),
      MediaItem(id: '4', title: 'Kooku Web Series'),
      MediaItem(id: '5', title: 'Explicit XXX Action', rating: '18+'),
      MediaItem(id: '6', title: 'Normal Title', description: 'Contains extreme pornography and nudity'),
    ];

    final filtered = filter.filterMediaList(adultItems);
    expect(filtered.isEmpty, isTrue);
  });

  test('Allows family safe titles', () async {
    final filter = ContentFilterService.instance;
    await filter.init();

    final safeItems = [
      MediaItem(id: '10', title: 'The Avengers', description: 'Earth mightiest heroes unite'),
      MediaItem(id: '11', title: 'Spider-Man: Homecoming', description: 'Peter Parker balances high school and superhero duties'),
      MediaItem(id: '12', title: 'Finding Nemo', description: 'A clown fish searches for his missing son'),
      MediaItem(id: '13', title: 'Interstellar', description: 'Explorers travel through a wormhole in space'),
      MediaItem(id: '14', title: 'Essex Boys', description: 'Crime drama set in Essex'), // Ensure Essex does not false trigger on sex
    ];

    final filtered = filter.filterMediaList(safeItems);
    expect(filtered.length, equals(safeItems.length));
  });

  test('Blocks explicit search queries (pussy, porn, xxx, sex)', () async {
    final filter = ContentFilterService.instance;
    await filter.init();

    expect(filter.isQueryNsfw('pussy'), isTrue);
    expect(filter.isQueryNsfw('PUSSY'), isTrue);
    expect(filter.isQueryNsfw('play with my pussy'), isTrue);
    expect(filter.isQueryNsfw('porn'), isTrue);
    expect(filter.isQueryNsfw('xxx adult'), isTrue);
    expect(filter.isQueryNsfw('fuck'), isTrue);

    // Safe queries are NOT blocked
    expect(filter.isQueryNsfw('Avengers'), isFalse);
    expect(filter.isQueryNsfw('Spider-Man'), isFalse);
    expect(filter.isQueryNsfw('Daredevil'), isFalse);
  });

  test('Blocks items tagged with Genre Adult or explicit titles', () async {
    final filter = ContentFilterService.instance;
    await filter.init();

    final explicitItems = [
      MediaItem(id: '101', title: 'Pussy fingering solo teen', genre: 'Adult'),
      MediaItem(id: '102', title: 'play with my pussy, but please don’t get me pregnant!', genre: 'Adult'),
      MediaItem(id: '103', title: 'Filled Ebony With So Much Cum!', genre: 'Adult'),
      MediaItem(id: '104', title: 'Action Film', genre: 'Adult'), // Blocked purely because genre is Adult
      MediaItem(id: '105', title: 'Stepsis Lets Me Rub Her', genre: 'Adult'),
      MediaItem(id: '106', title: 'City Girls - Pussy Talk ft. Doja Cat', genre: 'Pop'), // Blocked because title has pussy
    ];

    final filtered = filter.filterMediaList(explicitItems);
    expect(filtered.isEmpty, isTrue);
  });

  test('Toggle filter off allows all titles and persists', () async {
    final filter = ContentFilterService.instance;
    await filter.init();

    await filter.setFilterEnabled(false);
    expect(filter.isFilterEnabled, isFalse);

    final adultItem = MediaItem(id: '1', title: 'Sensual Night 18+');
    expect(filter.filterMediaList([adultItem]).length, equals(1));

    // Reset back to enabled
    await filter.setFilterEnabled(true);
    expect(filter.isFilterEnabled, isTrue);
  });

  test('Blocks Rx rated anime and nudity/hentai/ecchi content', () async {
    final filter = ContentFilterService.instance;
    await filter.init();

    final rxItems = [
      MediaItem(id: '201', title: 'Overflow', rating: 'Rx'),
      MediaItem(id: '202', title: 'Kuroinu', rating: 'Rx - Hentai'),
      MediaItem(id: '203', title: 'Anime Title Uncensored', genre: 'Ecchi, Hentai'),
      MediaItem(id: '204', title: 'Summer Memories', description: 'Full uncensored nudity and erotic scenes'),
      MediaItem(id: '205', title: 'Anime OVA', certification: 'Rx'),
      MediaItem(id: '206', title: 'Secret Desires', certification: 'R18+'),
    ];

    final filtered = filter.filterMediaList(rxItems);
    expect(filtered.isEmpty, isTrue);

    // Also verify isDetailDataNsfw
    expect(filter.isDetailDataNsfw({'title': 'Anime Show', 'rating': 'Rx - Hentai'}), isTrue);
    expect(filter.isDetailDataNsfw({'title': 'Show with explicit genre', 'genres': 'Hentai, Animation'}), isTrue);
    expect(filter.isDetailDataNsfw({'title': 'Demon Slayer', 'genres': 'Action, Fantasy', 'rating': 'PG-13'}), isFalse);
  });
}
