import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_models.dart';

/// Service responsible for filtering out NSFW, 18+, adult, and explicit titles.
/// Always enabled by default for family safety.
class ContentFilterService extends ChangeNotifier {
  static final ContentFilterService instance = ContentFilterService._();
  ContentFilterService._();

  static const String _prefsKey = 'nsfw_filter_enabled';
  bool _isFilterEnabled = true;

  bool get isFilterEnabled => _isFilterEnabled;

  /// Adult and NSFW keywords (matched as whole words or distinctive patterns)
  static final List<RegExp> _nsfwRegexPatterns = [
    // Age and rating flags
    RegExp(r'\b18\+', caseSensitive: false),
    RegExp(r'\b(nc-?17|r-?18|xxx|adult only|for adults)\b', caseSensitive: false),
    
    // Explicit themes and words
    RegExp(r'\b(erotic\w*|porn\w*|hentai|ecchi|softcore|hardcore|uncensored)\b', caseSensitive: false),
    RegExp(r'\b(nudity|nude\w*|strip club|stripper|sensual massage|lustful)\b', caseSensitive: false),
    RegExp(r'\b(sex|sexy|sexual\w*|fetish|voyeur|camgirl|escort|brothel)\b', caseSensitive: false),
    RegExp(r'\b(hot short|hot series|playboy|penthouse)\b', caseSensitive: false),

    // Indian adult web series platforms and tags (frequently appearing in aggregator databases)
    RegExp(
      r'\b(ullu|kooku|primeshots|primeplay|voovi|rabbit|bigshots|hunters|fliz|chikooflix|jalva|moodx|besharams|yessma|cinema dosti|gupchup|hotshots|red prime|bhabhi)\b',
      caseSensitive: false,
    ),
  ];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // Default is strictly true (always ON)
    _isFilterEnabled = prefs.getBool(_prefsKey) ?? true;
    notifyListeners();
  }

  Future<void> setFilterEnabled(bool enabled) async {
    _isFilterEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
    notifyListeners();
  }

  /// Checks whether a given string contains adult or NSFW markers.
  bool isNsfwString(String? text) {
    if (text == null || text.isEmpty) return false;
    for (final pattern in _nsfwRegexPatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether a MediaItem is considered NSFW.
  bool isNsfw(MediaItem item) {
    if (!_isFilterEnabled) return false;

    // Check title
    if (isNsfwString(item.title)) return true;

    // Check description/synopsis
    if (isNsfwString(item.description)) return true;

    // Check rating if it explicitly says 18+ or NC-17
    if (item.rating != null && isNsfwString(item.rating)) return true;

    return false;
  }

  /// Filters a list of MediaItems, dropping any item that matches NSFW criteria.
  List<MediaItem> filterMediaList(List<MediaItem> items) {
    if (!_isFilterEnabled) return items;
    return items.where((item) => !isNsfw(item)).toList();
  }
}
