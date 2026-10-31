# Netflix-Style Player, Continue Watching, Watchlist & Credits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete Netflix-style streaming experience for the standalone Android Flutter app: custom gesture player with double-tap seek, resolution/speed/aspect controls, local Continue Watching queue, Watchlist ("My List") system, a 4-tab bottom navigation shell, and a prominent Credits section ("Made by Hackedghost64").

**Architecture:** 
- `StorageService` manages all local persistent state (`WatchProgress` and `WatchlistItem`) via `SharedPreferences`.
- `NetflixPlayerScreen` handles high-performance direct video playback with custom overlay controls, gesture detectors for double-tap seeking, auto-save timers, in-player resolution switching, and series auto-next episode.
- `MainNavScreen` unifies the app under a 4-tab BottomNavigationBar (*Home*, *Continue Watching*, *My List*, *Downloads*).
- `HomeScreen` hosts horizontal scroll rows for *Continue Watching* and *My List* above the trending grid.
- Prominent styled Credits ("Made by Hackedghost64") integrated into the Settings dialog and About card.

**Tech Stack:** Flutter 3.41, Dart 3.11, `video_player`, `shared_preferences`, `url_launcher`, `open_filex`.

## Global Constraints
- Target platform: Android (minSdk 21).
- Theme: Dark Netflix aesthetic (#0F0F0F scaffold, #1E1E1E surface, #E50914 stream red accent).
- Credits exact text: **"Made by Hackedghost64"**.
- Code quality: 0 errors on `flutter analyze`.

---

### Task 1: Storage Models & StorageService

**Files:**
- Create: `app/lib/models/storage_models.dart`
- Create: `app/lib/services/storage_service.dart`
- Test: `app/test/storage_service_test.dart`

**Interfaces:**
- Produces:
  - `class WatchProgress` (subjectId, title, poster, season, episode, episodeTitle, positionMs, durationMs, lastWatchedMs, streamUrl, streamCookie)
  - `class WatchlistItem` (id, title, poster, year, rating, type, addedAtMs)
  - `class StorageService` with methods:
    - `Future<void> init()`
    - `Future<void> saveWatchProgress(WatchProgress progress)`
    - `WatchProgress? getWatchProgress(String id)`
    - `List<WatchProgress> getAllWatchProgress()`
    - `Future<void> removeWatchProgress(String id)`
    - `Future<bool> toggleWatchlist(MediaItem item)`
    - `bool isInWatchlist(String id)`
    - `List<WatchlistItem> getWatchlist()`
    - `Future<void> removeWatchlist(String id)`

- [ ] **Step 1: Write unit test for StorageService**

```dart
// app/test/storage_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbx_app/models/storage_models.dart';
import 'package:mbx_app/models/media_models.dart';
import 'package:mbx_app/services/storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Save and retrieve watch progress', () async {
    final storage = StorageService();
    await storage.init();

    final item = WatchProgress(
      subjectId: '12345',
      title: 'Spider-Man',
      poster: 'https://image.url',
      season: 0,
      episode: 0,
      positionMs: 60000,
      durationMs: 120000,
      lastWatchedMs: DateTime.now().millisecondsSinceEpoch,
    );

    await storage.saveWatchProgress(item);
    final retrieved = storage.getWatchProgress('12345');
    expect(retrieved, isNotNull);
    expect(retrieved!.title, 'Spider-Man');
    expect(retrieved.progressPercentage, closeTo(0.5, 0.01));
  });

  test('Toggle and retrieve watchlist item', () async {
    final storage = StorageService();
    await storage.init();

    final media = MediaItem(
      id: '999',
      title: 'Batman',
      poster: 'https://poster.url',
      year: '2022',
      type: 1,
    );

    expect(storage.isInWatchlist('999'), isFalse);
    final added = await storage.toggleWatchlist(media);
    expect(added, isTrue);
    expect(storage.isInWatchlist('999'), isTrue);

    final list = storage.getWatchlist();
    expect(list.length, 1);
    expect(list.first.title, 'Batman');

    final removed = await storage.toggleWatchlist(media);
    expect(removed, isFalse);
    expect(storage.isInWatchlist('999'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify failure**
Run: `flutter test test/storage_service_test.dart`
Expected: Compilation failure (files don't exist yet).

- [ ] **Step 3: Implement `storage_models.dart`**
Create `app/lib/models/storage_models.dart` defining `WatchProgress` and `WatchlistItem` with full JSON serialization and `progressPercentage` getter.

- [ ] **Step 4: Implement `storage_service.dart`**
Create `app/lib/services/storage_service.dart` with singleton instance and SharedPreferences persistence.

- [ ] **Step 5: Run tests and verify PASS**
Run: `flutter test test/storage_service_test.dart`
Expected: All tests pass.

---

### Task 2: Netflix-Style Video Player (`NetflixPlayerScreen`)

**Files:**
- Create: `app/lib/screens/netflix_player_screen.dart`
- Modify: `app/lib/screens/detail_screen.dart` (point play action to `NetflixPlayerScreen`)

**Interfaces:**
- Consumes:
  - `StreamOption`, `MediaItem`, `StorageService.instance`
- Produces:
  - `NetflixPlayerScreen` widget with gesture detection:
    - Double-tap left: seek -10s with ripple icon
    - Double-tap right: seek +10s with ripple icon
    - Top bar: back button, title, episode label, external player launcher
    - Center bar: quick -10s, play/pause, quick +10s, screen lock toggle
    - Bottom bar: elapsed time, total time, red progress slider, quality switcher button, playback speed button, aspect ratio switcher button, next episode button (if series)
    - Auto-save timer updating `StorageService.instance.saveWatchProgress` every 5 seconds.

- [ ] **Step 1: Implement `netflix_player_screen.dart`**
Create `app/lib/screens/netflix_player_screen.dart` implementing full custom UI controls over `VideoPlayerController` with auto-hide timer (4 seconds), double-tap seek animation overlays, speed picker dialog, resolution switcher, and screen lock.

- [ ] **Step 2: Update `detail_screen.dart`**
Replace navigation to old `PlayerScreen` with `NetflixPlayerScreen` in `_StreamSelectorSheet`.

- [ ] **Step 3: Verify analyzer**
Run: `flutter analyze`
Expected: 0 errors.

---

### Task 3: Watchlist Integration on DetailScreen

**Files:**
- Modify: `app/lib/screens/detail_screen.dart`

**Interfaces:**
- Consumes: `StorageService.instance.isInWatchlist`, `StorageService.instance.toggleWatchlist`
- Produces:
  - Responsive "+ My List" / "✓ In My List" toggle button next to "Watch Movie" and "Download" buttons.

- [ ] **Step 1: Add Watchlist button to `detail_screen.dart`**
Add an interactive button with icon (`Icons.check` or `Icons.add`) next to "Watch Movie" and "Download". Tapping updates local state and saves to `StorageService.instance.toggleWatchlist()`.

- [ ] **Step 2: Verify analyzer**
Run: `flutter analyze`
Expected: 0 errors.

---

### Task 4: Continue Watching & My List Screens

**Files:**
- Create: `app/lib/screens/continue_watching_screen.dart`
- Create: `app/lib/screens/watchlist_screen.dart`

**Interfaces:**
- Consumes: `StorageService.instance`
- Produces:
  - `ContinueWatchingScreen`: List of active progress cards with red progress bar, remaining time badge, 1-tap resume directly to `NetflixPlayerScreen`, and swipe-to-delete.
  - `WatchlistScreen`: Grid view of bookmarked movies and series with tap to open `DetailScreen` and swipe-to-delete.

- [ ] **Step 1: Implement `continue_watching_screen.dart`**
Create `app/lib/screens/continue_watching_screen.dart` with pull-to-refresh, clear-all action, and resume cards.

- [ ] **Step 2: Implement `watchlist_screen.dart`**
Create `app/lib/screens/watchlist_screen.dart` with grid cards, badge for Movie/Series, and tap to view details.

- [ ] **Step 3: Verify analyzer**
Run: `flutter analyze`
Expected: 0 errors.

---

### Task 5: 4-Tab Bottom Navigation Bar & Home Screen Carousels & Credits

**Files:**
- Create: `app/lib/screens/main_nav_screen.dart`
- Modify: `app/lib/screens/home_screen.dart`
- Modify: `app/lib/main.dart`

**Interfaces:**
- Produces:
  - `MainNavScreen`: BottomNavigationBar with 4 tabs:
    0: Home
    1: Continue Watching
    2: My List
    3: Downloads
  - `HomeScreen`:
    - Renders horizontal row for "Continue Watching" when progress items exist.
    - Renders horizontal row for "My List" when watchlist items exist.
    - Settings Dialog and Home footer with prominent:
      **"Made by Hackedghost64"** badge in crimson neon styling with developer credit.
  - `main.dart`: Sets `home: const MainNavScreen()`.

- [ ] **Step 1: Implement `main_nav_screen.dart`**
Create `app/lib/screens/main_nav_screen.dart` hosting the 4 views with smooth page switching and dark theme styling.

- [ ] **Step 2: Add rows & Credits to `home_screen.dart`**
Add Continue Watching horizontal carousel, My List horizontal carousel, and update Settings dialog to feature **"Made by Hackedghost64"**.

- [ ] **Step 3: Update `main.dart`**
Set `home: const MainNavScreen()` and initialize `StorageService.instance.init()`.

- [ ] **Step 4: Verify analyzer**
Run: `flutter analyze`
Expected: 0 errors.

---

### Task 6: Comprehensive Verification & Release APK Build

**Files:**
- Output: `app/build/app/outputs/flutter-apk/app-release.apk`
- Deliverable: `/home/divyam/Downloads/MBX_Stream.apk`

- [ ] **Step 1: Run all unit tests**
Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 2: Run Flutter analyze**
Run: `flutter analyze`
Expected: 0 errors.

- [ ] **Step 3: Build release APK**
Run: `flutter build apk --release`
Expected: Build exit code 0.

- [ ] **Step 4: Copy to Downloads directories**
Copy to:
- `/home/divyam/Downloads/MBX_Stream.apk`
- `/home/divyam/Downloads/projects/movie-app/downloads/MBX_Stream.apk`
- `/home/divyam/Downloads/projects/movie-app/MBX_Stream.apk`
