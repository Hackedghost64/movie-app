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
}
