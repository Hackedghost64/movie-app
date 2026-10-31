# Specification: Netflix-Style Player, Continue Watching, Watchlist & Credits

**Date:** 2026-09-13  
**Status:** Approved by User  
**Target Platform:** Android (Flutter app `mbx_app`)

---

## 1. Overview
This specification details the addition of four core features to the standalone `MBX Stream` Android client:
1. A **Netflix-style custom video player** featuring responsive gesture controls (double-tap 10s seek, swipe brightness/volume, custom HUD controls, speed controller, aspect ratio toggle, screen lock, and next-episode button).
2. A **Continue Watching system** with persistent progress tracking in local storage (`SharedPreferences`) and an interactive horizontal carousel with progress bars and 1-tap resume.
3. A **Watchlist ("My List") system** allowing bookmarking from `DetailScreen` and viewing on Home or a dedicated tab.
4. A **Bottom Navigation Bar** providing 4 tabs: *Home*, *Continue Watching*, *My List*, and *Downloads*.
5. A **Credits & About Section** clearly displaying **"Made by Hackedghost64"** in the app header/settings dialog with stylized dark theme branding.

---

## 2. Architecture & Data Models

### 2.1 Persistence Service (`lib/services/storage_service.dart`)
A dedicated storage helper using `SharedPreferences` to manage:
- **Continue Watching Items**:
  ```dart
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
  }
  ```
  - Auto-updates progress on player tick (every 5 seconds) and player dispose.
  - Removes from Continue Watching once progress exceeds 92% (considered completed).
  - Provides methods: `saveProgress()`, `getProgress(id)`, `getAllProgress()`, `removeProgress(id)`, `clearAll()`.

- **Watchlist Items**:
  ```dart
  class WatchlistItem {
    final String id;
    final String title;
    final String? poster;
    final String? year;
    final String? rating;
    final int? type; // 1 = Movie, 2 = Series
    final int addedAtMs;
  }
  ```
  - Methods: `toggleWatchlist(MediaItem)`, `isBookmarked(id)`, `getWatchlist()`, `removeWatchlist(id)`.

---

## 3. Component Details

### 3.1 Netflix-Style Video Player (`lib/screens/netflix_player_screen.dart`)
Replaces basic Chewie/VideoPlayer with a purpose-built Netflix-inspired player interface:
- **Gestures**:
  - Double-tap left side: Rewinds 10s with visual overlay (`-10s`).
  - Double-tap right side: Fast-forwards 10s with visual overlay (`+10s`).
  - Single tap: Toggles overlay visibility with a 4-second auto-hide timer.
- **HUD Layout**:
  - **Top Bar**:
    - Back button, media title, season/episode subtitle.
    - Quick actions: Aspect ratio toggle (`Fit` / `Fill` / `16:9`), Audio/Speed menu, External player launcher.
  - **Center Overlay**:
    - Large Play/Pause icon with -10s and +10s quick buttons.
    - Lock screen button (disables all touch controls until unlocked).
  - **Bottom Bar**:
    - Current time and total duration.
    - Red Netflix-style timeline slider.
    - Quality badge (e.g., `1080p`) allowing in-player quality switching without restarting.
    - Next Episode floating button (appears if watching series when `positionMs > durationMs - 45000`).
- **State Recovery**:
  - On launch, queries `StorageService.getProgress(subjectId)`. If `positionMs > 10000`, prompts or automatically seeks to saved position.

### 3.2 Continue Watching Row & Screen
- **Horizontal Carousel on Home**:
  - Placed directly under the search bar.
  - Poster cards with bottom red progress bar (`positionMs / durationMs`).
  - Subtitle: "S1:E3" for series, or time remaining (e.g. "42m left").
  - 1-Tap play icon directly on the card to resume playback immediately.
- **Dedicated Continue Watching Tab**:
  - Full list with thumbnail, title, remaining time, and swipe-to-remove.

### 3.3 Watchlist ("My List")
- **Detail Screen Integration**:
  - Prominent "+ My List" / "✓ In My List" toggle button right next to "Watch Movie" / "Download".
- **Home Carousel**:
  - "My List" horizontal row on the Home feed.
- **Dedicated My List Tab**:
  - Grid view of all saved movies and TV series.

### 3.4 Bottom Navigation & Credits
- **Bottom Navigation Bar**:
  - 4 Tabs:
    1. `Home` (Search, Continue Watching row, My List row, Trending & Popular grid).
    2. `Continue Watching` (In-progress queue with resume buttons).
    3. `My List` (Saved movies & series).
    4. `Downloads` (Offline downloads manager).
- **Credits & About Section**:
  - Added to Settings Dialog & Bottom of Home Screen:
    - **"Made by Hackedghost64"** with a glowing crimson badge and app version info.

---

## 4. Error Handling & Edge Cases
- If a stream URL expires or session token refreshes, player retains the current seek position, fetches a refreshed stream URL via `MovieBoxApi.getStreams()`, and resumes smoothly.
- Movies correctly resume with `season=0, episode=0`.
- Offline/downloaded items can also be tracked if played locally.

---

## 5. Verification Plan
- Unit test coverage for `StorageService` (adding, updating progress, removing, completing >92%).
- Full `flutter analyze` ensuring 0 compilation errors.
- Build release APK and verify on Android.
