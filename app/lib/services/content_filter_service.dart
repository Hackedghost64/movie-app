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
    
    // Genitalia and sexual anatomy
    RegExp(r'\b(pussy|pussies|dick|dicks|cock|cocks|vagina|vaginas|penis|penises|clit|clitoris|boob|boobs|tits|titties|asshole|dildo|dildos|anus|nipple|nipples|pubic)\b', caseSensitive: false),

    // Sexual acts, fluids, and pornography
    RegExp(
      r'\b(fucking|fuck|fucked|fingering|creampie\w*|squirt|squirting|squirts|blowjob\w*|handjob\w*|cum|cumming|cums|deepthroat|orgasm\w*|masturbat\w*|intercourse|penetrat\w*|ejaculat\w*|gangbang|orgy|threesome|doggystyle|doggy style|bdsm|bondage|sex toy|pleasure toy)\b',
      caseSensitive: false,
    ),

    // Adult genres, themes, and tags
    RegExp(
      r'\b(adult|erotic\w*|porn\w*|hentai|ecchi|softcore|hardcore|uncensored|jav|javhd|taboo|incest|stepsister|stepdaughter|stepmom|stepsis|bhabhi|milf|camgirl|escort|brothel|stripper|strip club|nudity|nude\w*|lustful|sensual massage|fetish|voyeur|playboy|penthouse|busty|slut|whore)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b(sex|sexy|sexual\w*)\b', caseSensitive: false),
    RegExp(r'\b(hot short|hot series)\b', caseSensitive: false),

    // Indian adult web series platforms and tags (frequently appearing in aggregator databases)
    RegExp(
      r'\b(ullu|kooku|primeshots|primeplay|voovi|rabbit|bigshots|hunters|fliz|chikooflix|jalva|moodx|besharams|yessma|cinema dosti|gupchup|hotshots|red prime)\b',
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

  /// Checks whether a search query is considered NSFW.
  bool isQueryNsfw(String query) {
    if (!_isFilterEnabled) return false;
    return isNsfwString(query);
  }

  /// Checks whether a MediaItem is considered NSFW.
  bool isNsfw(MediaItem item) {
    if (!_isFilterEnabled) return false;

    // Check upstream category/genre
    if (item.genre != null) {
      final g = item.genre!.toLowerCase();
      if (g.contains('adult') || isNsfwString(g)) return true;
    }

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
