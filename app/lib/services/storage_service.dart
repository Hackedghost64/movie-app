import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_models.dart';
import '../models/storage_models.dart';

class StorageService extends ChangeNotifier {
  static final StorageService instance = StorageService();

  static const String _watchProgressKey = 'mbx_watch_progress_v1';
  static const String _watchlistKey = 'mbx_watchlist_v1';

  SharedPreferences? _prefs;
  final Map<String, WatchProgress> _watchProgress = {};
  final Map<String, WatchlistItem> _watchlist = {};

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _loadFromPrefs();
  }

  void _loadFromPrefs() {
    _watchProgress.clear();
    _watchlist.clear();

    final progressJson = _prefs?.getString(_watchProgressKey);
    if (progressJson != null && progressJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(progressJson);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              _watchProgress[key] = WatchProgress.fromJson(value);
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading watch progress: $e');
      }
    }

    final watchlistJson = _prefs?.getString(_watchlistKey);
    if (watchlistJson != null && watchlistJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(watchlistJson);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              _watchlist[key] = WatchlistItem.fromJson(value);
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading watchlist: $e');
      }
    }
  }

  Future<void> _ensureInit() async {
    if (_prefs == null) {
      await init();
    }
  }

  Future<void> _persistWatchProgress() async {
    if (_prefs == null) return;
    final map = _watchProgress.map((k, v) => MapEntry(k, v.toJson()));
    await _prefs!.setString(_watchProgressKey, jsonEncode(map));
  }

  Future<void> _persistWatchlist() async {
    if (_prefs == null) return;
    final map = _watchlist.map((k, v) => MapEntry(k, v.toJson()));
    await _prefs!.setString(_watchlistKey, jsonEncode(map));
  }

  Future<void> saveWatchProgress(WatchProgress progress) async {
    await _ensureInit();
    _watchProgress[progress.subjectId] = progress;
    await _persistWatchProgress();
    notifyListeners();
  }

  WatchProgress? getWatchProgress(String id) {
    return _watchProgress[id];
  }

  List<WatchProgress> getAllWatchProgress() {
    final list = _watchProgress.values.toList();
    list.sort((a, b) => b.lastWatchedMs.compareTo(a.lastWatchedMs));
    return list;
  }

  Future<void> removeWatchProgress(String id) async {
    await _ensureInit();
    _watchProgress.remove(id);
    await _persistWatchProgress();
    notifyListeners();
  }

  Future<bool> toggleWatchlist(MediaItem item) async {
    await _ensureInit();
    final bool added;
    if (_watchlist.containsKey(item.id)) {
      _watchlist.remove(item.id);
      added = false;
    } else {
      _watchlist[item.id] = WatchlistItem.fromMediaItem(item);
      added = true;
    }
    await _persistWatchlist();
    notifyListeners();
    return added;
  }

  bool isInWatchlist(String id) {
    return _watchlist.containsKey(id);
  }

  List<WatchlistItem> getWatchlist() {
    final list = _watchlist.values.toList();
    list.sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));
    return list;
  }

  Future<void> removeWatchlist(String id) async {
    await _ensureInit();
    _watchlist.remove(id);
    await _persistWatchlist();
    notifyListeners();
  }
}
