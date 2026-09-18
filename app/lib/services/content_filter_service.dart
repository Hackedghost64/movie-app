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
    // Age, certification, and maturity rating flags (including Anime Rx rating)
    RegExp(r'\b18\+', caseSensitive: false),
    RegExp(r'\b(rx|rx-?hentai|rx-?rated|nc-?17|r-?18\+?|r18\+?|xxx|adult only|for adults|rated r-?18|x-?rated|mature 18\+?|tv-?ma)\b', caseSensitive: false),
    RegExp(r'\b(r\+|r\s*\+)\b', caseSensitive: false), // R+ rating in anime
    
    // Genitalia and sexual anatomy
    RegExp(r'\b(pussy|pussies|dick|dicks|cock|cocks|vagina|vaginas|penis|penises|clit|clitoris|boob|boobs|tits|titties|asshole|dildo|dildos|anus|nipple|nipples|pubic)\b', caseSensitive: false),

    // Sexual acts, fluids, and pornography
    RegExp(
      r'\b(fucking|fuck|fucked|fingering|creampie\w*|squirt|squirting|squirts|blowjob\w*|handjob\w*|cum|cumming|cums|deepthroat|orgasm\w*|masturbat\w*|intercourse|penetrat\w*|ejaculat\w*|gangbang|orgy|threesome|doggystyle|doggy style|bdsm|bondage|sex toy|pleasure toy)\b',
      caseSensitive: false,
    ),

    // Adult genres, themes, nudity, and explicit tags
    RegExp(
      r'\b(adult|erotic\w*|porn\w*|hentai|ecchi|ahegao|doujin\w*|eroge|eromanga|smut|yaoi|yuri|softcore|hardcore|uncensored|no censor\w*|unrated|jav|javhd|taboo|incest|stepsister|stepdaughter|stepmom|stepsis|bhabhi|milf|camgirl|escort|brothel|stripper|strip club|nudity|nude\w*|naked\w*|lewd\w*|lustful|sensual massage|fetish|voyeur|playboy|penthouse|busty|slut|whore|chikan|netorare|ntr|oppai|sukumizu)\b',
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
    if (text == null || text.trim().isEmpty) return false;
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

    // Check upstream category/genre/tags
    if (item.genre != null) {
      final g = item.genre!.toLowerCase();
      if (g.contains('adult') || g.contains('hentai') || g.contains('ecchi') || isNsfwString(g)) return true;
    }

    // Check title
    if (isNsfwString(item.title)) return true;

    // Check description/synopsis
    if (isNsfwString(item.description)) return true;

    // Check rating (e.g. Rx, R18+, NC-17)
    if (item.rating != null) {
      final r = item.rating!.trim().toLowerCase();
      if (r == 'rx' || r.contains('rx') || r.contains('r18') || r.contains('nc-17') || isNsfwString(r)) {
        return true;
      }
    }

    // Check certification / ageRating
    if (item.certification != null) {
      final c = item.certification!.trim().toLowerCase();
      if (c == 'rx' || c.contains('rx') || c.contains('r18') || c.contains('nc-17') || isNsfwString(c)) {
        return true;
      }
    }

    return false;
  }

  /// Checks whether a raw API response map contains NSFW markers.
  bool isDetailDataNsfw(Map<String, dynamic> data) {
    if (!_isFilterEnabled) return false;

    final title = (data['title'] ?? data['subjectName'] ?? data['name'] ?? '').toString();
    if (isNsfwString(title)) return true;

    final desc = (data['description'] ?? data['synopsis'] ?? data['desc'] ?? '').toString();
    if (isNsfwString(desc)) return true;

    final genre = (data['genre'] ?? data['genres'] ?? data['category'] ?? data['tag'] ?? data['classify'] ?? data['tags'] ?? '').toString();
    if (genre.toLowerCase().contains('adult') || isNsfwString(genre)) return true;

    final cert = (data['certification'] ?? data['ageRating'] ?? data['contentRating'] ?? data['rating'] ?? data['parentalRating'] ?? '').toString();
    final c = cert.trim().toLowerCase();
    if (c == 'rx' || c.contains('rx') || c.contains('r18') || c.contains('nc-17') || isNsfwString(c)) {
      return true;
    }

    return false;
  }

  /// Filters a list of MediaItems, dropping any item that matches NSFW criteria.
  List<MediaItem> filterMediaList(List<MediaItem> items) {
    if (!_isFilterEnabled) return items;
    return items.where((item) => !isNsfw(item)).toList();
  }
}
