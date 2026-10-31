import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_models.dart';
import 'content_filter_service.dart';

class MovieBoxApi {
  static final MovieBoxApi instance = MovieBoxApi._();
  MovieBoxApi._();

  // Reverse-engineered constants from APK v4.0.02.0831.03
  static const String gatewaySecretOnline = "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O";
  static const String defaultApiHost = "api6.aoneroom.com";
  static const String appPackage = "com.community.oneroom";
  static const String appVersion = "4.0.03.0922.03";
  static const int appVersionCode = 50020131;

  String? _deviceId;
  String? _sessionToken;
  Completer<void>? _bootstrapCompleter;

  bool useGateway = false;
  String gatewayUrl = "http://10.0.2.2:8399";
  String? gatewayApiKey;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString("device_id");
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await prefs.setString("device_id", _deviceId!);
    }
    _sessionToken = prefs.getString("session_token");
    useGateway = prefs.getBool("use_gateway") ?? false;
    gatewayUrl = prefs.getString("gateway_url") ?? "http://10.0.2.2:8399";
    gatewayApiKey = prefs.getString("gateway_api_key");

    // Proactively warm up anonymous session if direct mode
    if (!useGateway && (_sessionToken == null || _sessionToken!.isEmpty)) {
      try {
        await _bootstrapSession();
      } catch (e) {
        debugPrint("Initial session bootstrap failed: $e");
      }
    }
  }

  Future<void> saveSettings({required bool gateway, required String url, String? apiKey}) async {
    useGateway = gateway;
    gatewayUrl = url;
    gatewayApiKey = apiKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("use_gateway", gateway);
    await prefs.setString("gateway_url", url);
    if (apiKey != null) {
      await prefs.setString("gateway_api_key", apiKey);
    }
  }

  String _generateDeviceId() {
    final rand = DateTime.now().microsecondsSinceEpoch.toString();
    return md5.convert(utf8.encode(rand)).toString();
  }

  String _generateClientToken() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final reversed = ts.split('').reversed.join('');
    final digest = md5.convert(utf8.encode(reversed)).toString();
    return "$ts,$digest";
  }

  String _generateClientInfo() {
    final info = {
      "package_name": appPackage,
      "version_name": appVersion,
      "version_code": appVersionCode,
      "os": "android",
      "os_version": "14",
      "device_id": _deviceId ?? "device_default",
      "install_store": "google_play",
      "brand": "Google",
      "model": "Pixel 8 Pro",
      "system_language": "en",
      "net": "WIFI",
      "region": "US",
      "timezone": "America/New_York",
      "sp_code": "0"
    };
    return jsonEncode(info);
  }

  String _canonicalizeQuery(String queryString) {
    if (queryString.isEmpty) return "";
    final parts = queryString.split("&");
    final Map<String, String> map = {};
    for (var part in parts) {
      if (part.isEmpty) continue;
      final idx = part.indexOf("=");
      final kRaw = idx >= 0 ? part.substring(0, idx) : part;
      final vRaw = idx >= 0 ? part.substring(idx + 1) : "";
      try {
        final k = Uri.decodeComponent(kRaw);
        final v = Uri.decodeComponent(vRaw);
        if (k.isNotEmpty) map[k] = v;
      } catch (_) {
        map[kRaw] = vRaw;
      }
    }
    final sortedKeys = map.keys.toList()..sort();
    return sortedKeys.map((k) => "$k=${map[k]}").join("&");
  }

  String _generateSignature({
    required String method,
    required String path,
    required String rawQuery,
    required Map<String, String> headers,
    required List<int>? bodyBytes,
    required int timestampMs,
  }) {
    final accept = headers["accept"] ?? "";
    final contentType = headers["content-type"] ?? "";
    final contentLength = headers["content-length"] ?? "";
    final bodyMd5 = (bodyBytes != null && bodyBytes.isNotEmpty)
        ? md5.convert(bodyBytes.sublist(0, bodyBytes.length > 102400 ? 102400 : bodyBytes.length)).toString()
        : "";
    final cq = _canonicalizeQuery(rawQuery);
    final pathQuery = cq.isNotEmpty ? "$path?$cq" : path;

    final canonical = [
      method.toUpperCase(),
      accept,
      contentType,
      contentLength,
      timestampMs.toString(),
      bodyMd5,
      pathQuery,
    ].join("\n");

    final secretBytes = base64.decode(gatewaySecretOnline);
    final hmacMd5 = Hmac(md5, secretBytes);
    final digest = hmacMd5.convert(utf8.encode(canonical));
    final digestB64 = base64.encode(digest.bytes);

    return "$timestampMs|2|$digestB64";
  }

  /// Bootstraps an anonymous session token via search-suggest endpoint.
  Future<void> _bootstrapSession({bool force = false}) async {
    if (!force && _sessionToken != null && _sessionToken!.isNotEmpty) return;
    if (_bootstrapCompleter != null) return _bootstrapCompleter!.future;

    _bootstrapCompleter = Completer<void>();
    try {
      await _requestDirectRaw(
        "GET",
        "/wefeed-mobile-bff/subject-api/search-suggest",
        params: {"q": "a"},
      );
      if (!_bootstrapCompleter!.isCompleted) {
        _bootstrapCompleter!.complete();
      }
    } catch (e) {
      if (!_bootstrapCompleter!.isCompleted) {
        _bootstrapCompleter!.completeError(e);
      }
      _bootstrapCompleter!.future.catchError((_) {});
      rethrow;
    } finally {
      _bootstrapCompleter = null;
    }
  }

  Future<Map<String, dynamic>> _requestDirectRaw(
    String method,
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? jsonBody,
  }) async {
    final paramMap = Map<String, String>.from(params ?? {});
    final queryParts = <String>[];
    paramMap.forEach((k, v) {
      queryParts.add("${Uri.encodeComponent(k)}=${Uri.encodeComponent(v)}");
    });
    final rawQuery = queryParts.join("&");

    final uri = Uri.parse("https://$defaultApiHost$path${rawQuery.isNotEmpty ? '?$rawQuery' : ''}");
    final ts = DateTime.now().millisecondsSinceEpoch;
    final clientToken = _generateClientToken();

    final headers = <String, String>{
      "accept": "application/json, text/plain, */*",
      "user-agent": "MovieBox/$appVersion (Android 14; Pixel 8 Pro)",
      "x-tr-app": appPackage,
      "x-tr-version": appVersion,
      "x-tr-device": _deviceId ?? "device_default",
      "x-tr-region": "US",
      "X-Client-Status": "1",
      "X-Client-Info": _generateClientInfo(),
      "x-client-token": clientToken,
      "token": clientToken,
    };

    if (_sessionToken != null && _sessionToken!.isNotEmpty) {
      headers.remove("x-client-token");
      headers.remove("token");
      headers["Authorization"] = "Bearer $_sessionToken";
    }

    List<int>? bodyBytes;
    if (jsonBody != null) {
      bodyBytes = utf8.encode(jsonEncode(jsonBody));
      headers["content-type"] = "application/json";
      headers["content-length"] = bodyBytes.length.toString();
    }

    final sig = _generateSignature(
      method: method,
      path: path,
      rawQuery: rawQuery,
      headers: headers,
      bodyBytes: bodyBytes,
      timestampMs: ts,
    );
    headers["x-tr-signature"] = sig;

    http.Response response;
    if (method.toUpperCase() == "POST") {
      response = await http.post(uri, headers: headers, body: bodyBytes);
    } else {
      response = await http.get(uri, headers: headers);
    }

    // Auto-harvest X-User token if provided in response headers
    final xUser = response.headers["x-user"];
    if (xUser != null && xUser.isNotEmpty) {
      try {
        final userData = jsonDecode(xUser);
        final token = userData["token"];
        if (token != null && token is String) {
          _sessionToken = token;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("session_token", token);
        }
      } catch (_) {}
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception("Upstream error (${response.statusCode}): ${response.body}");
    }
  }

  Future<Map<String, dynamic>> _requestDirect(
    String method,
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? jsonBody,
  }) async {
    // Ensure session token exists
    if (_sessionToken == null || _sessionToken!.isEmpty) {
      await _bootstrapSession();
    }

    try {
      return await _requestDirectRaw(method, path, params: params, jsonBody: jsonBody);
    } catch (e) {
      final errStr = e.toString();
      // Handle upstream 441 (miss token) or 401 unauthorized
      if (errStr.contains("441") || errStr.contains("401") || errStr.contains("miss token") || errStr.contains("UNAUTHORIZED")) {
        debugPrint("Session token rejected ($errStr). Refreshing and retrying...");
        _sessionToken = null;
        await _bootstrapSession(force: true);
        return await _requestDirectRaw(method, path, params: params, jsonBody: jsonBody);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestGateway(String path, {Map<String, dynamic>? params}) async {
    final base = gatewayUrl.endsWith("/") ? gatewayUrl.substring(0, gatewayUrl.length - 1) : gatewayUrl;
    final uri = Uri.parse("$base$path").replace(queryParameters: params?.map((k, v) => MapEntry(k, v.toString())));
    final headers = <String, String>{
      "accept": "application/json",
    };
    if (gatewayApiKey != null && gatewayApiKey!.isNotEmpty) {
      headers["X-API-Key"] = gatewayApiKey!;
    }
    final res = await http.get(uri, headers: headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception("Gateway error (${res.statusCode}): ${res.body}");
    }
  }

  // ---------------- Public API Methods ----------------

  Future<List<MediaItem>> search(String query) async {
    if (ContentFilterService.instance.isQueryNsfw(query)) {
      debugPrint("Search query '$query' blocked by Family Safe filter.");
      return [];
    }
    List<MediaItem> rawItems = [];
    if (useGateway) {
      final res = await _requestGateway("/search", params: {"q": query});
      final results = res["normalized"]?["results"] as List? ?? res["results"] as List? ?? [];
      rawItems = results.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      final res = await _requestDirect(
        "POST",
        "/wefeed-mobile-bff/subject-api/search/v2",
        params: {"host": defaultApiHost},
        jsonBody: {"page": 1, "perPage": 20, "keyword": query},
      );
      final List<MediaItem> items = [];
      final seenIds = <String>{};
      final data = res["data"];
      if (data != null) {
        final results = data["results"] as List? ?? data["items"] as List? ?? [];
        for (var section in results) {
          if (section is Map<String, dynamic>) {
            final subjects = section["subjects"] as List?;
            if (subjects != null && subjects.isNotEmpty) {
              for (var s in subjects) {
                if (s is Map<String, dynamic>) {
                  final item = MediaItem.fromJson(s);
                  if (item.id.isNotEmpty && !seenIds.contains(item.id)) {
                    seenIds.add(item.id);
                    items.add(item);
                  }
                }
              }
            } else if (section.containsKey("subjectId") || section.containsKey("id") || section.containsKey("title")) {
              final item = MediaItem.fromJson(section);
              if (item.id.isNotEmpty && !seenIds.contains(item.id)) {
                seenIds.add(item.id);
                items.add(item);
              }
            }
          }
        }
      }
      rawItems = items;
    }
    return ContentFilterService.instance.filterMediaList(rawItems);
  }

  Future<List<MediaItem>> getTopRank() async {
    List<MediaItem> rawItems = [];
    if (useGateway) {
      final res = await _requestGateway("/search/rank");
      final list = res["data"]?["list"] as List? ?? [];
      rawItems = list.map((e) => MediaItem.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      final res = await _requestDirect("GET", "/wefeed-mobile-bff/subject-api/search-rank/v2");
      final List<MediaItem> items = [];
      final seenIds = <String>{};
      final data = res["data"];
      if (data != null) {
        // Upstream returns { "hot": [ { "name": "Hot Movies", "items": [...] }, { "name": "Hot Series", "items": [...] } ] }
        if (data["hot"] is List) {
          for (var cat in data["hot"]) {
            if (cat is Map && cat["items"] is List) {
              for (var rawItem in cat["items"]) {
                if (rawItem is Map<String, dynamic>) {
                  final item = MediaItem.fromJson(rawItem);
                  if (item.id.isNotEmpty && !seenIds.contains(item.id)) {
                    seenIds.add(item.id);
                    items.add(item);
                  }
                }
              }
            }
          }
        }
        if (items.isEmpty && data["list"] is List) {
          for (var r in data["list"]) {
            if (r is Map<String, dynamic>) {
              final item = MediaItem.fromJson(r);
              if (item.id.isNotEmpty && !seenIds.contains(item.id)) {
                seenIds.add(item.id);
                items.add(item);
              }
            }
          }
        }
        if (items.isEmpty && data["items"] is List) {
          for (var r in data["items"]) {
            if (r is Map<String, dynamic>) {
              final item = MediaItem.fromJson(r);
              if (item.id.isNotEmpty && !seenIds.contains(item.id)) {
                seenIds.add(item.id);
                items.add(item);
              }
            }
          }
        }
      }
      rawItems = items;
    }
    return ContentFilterService.instance.filterMediaList(rawItems);
  }

  Future<List<MediaItem>> getTopMovies() async {
    final all = await getTopRank();
    return all.where((item) => item.type != 2).toList();
  }

  Future<List<MediaItem>> getTopSeries() async {
    final all = await getTopRank();
    return all.where((item) => item.type == 2).toList();
  }

  Future<List<MediaItem>> getByCategory(String category) async {
    if (category == 'All') {
      return await getTopRank();
    }
    if (category == 'Movies') {
      return await getTopMovies();
    }
    if (category == 'TV Series') {
      return await getTopSeries();
    }
    // Search by category / genre keyword
    final results = await search(category);
    return ContentFilterService.instance.filterMediaList(results);
  }

  Future<Map<String, dynamic>> getDetails(String subjectId) async {
    if (useGateway) {
      return await _requestGateway("/titles/$subjectId");
    } else {
      return await _requestDirect("GET", "/wefeed-mobile-bff/subject-api/get", params: {
        "host": defaultApiHost,
        "subjectId": subjectId,
      });
    }
  }

  Future<List<SeasonItem>> getSeasons(String subjectId) async {
    if (useGateway) {
      final res = await _requestGateway("/titles/$subjectId/seasons");
      final list = res["data"]?["seasons"] as List? ?? res["data"]?["items"] as List? ?? [];
      return list.map((s) => SeasonItem(
        seasonNumber: s["season"] ?? s["se"] ?? 1,
        title: s["title"] ?? "Season ${s['season'] ?? s['se'] ?? 1}",
        episodeCount: s["episodeCount"] ?? s["episodes"] ?? s["maxEp"] ?? 10,
      )).toList();
    } else {
      final res = await _requestDirect("GET", "/wefeed-mobile-bff/subject-api/season-info", params: {
        "host": defaultApiHost,
        "subjectId": subjectId,
      });
      final List<SeasonItem> seasons = [];
      final list = res["data"]?["seasons"] as List? ?? [];
      for (var s in list) {
        final seNum = s["se"] ?? s["season"] ?? 1;
        final maxEp = s["maxEp"] ?? s["maxEpisode"] ?? s["episodeCount"] ?? 0;
        final parsedSe = seNum is int ? seNum : int.tryParse(seNum.toString()) ?? 1;
        final parsedEp = maxEp is int ? maxEp : int.tryParse(maxEp.toString()) ?? 0;
        if (parsedSe > 0 && parsedEp > 0) {
          seasons.add(SeasonItem(
            seasonNumber: parsedSe,
            title: s["title"]?.toString() ?? "Season $parsedSe",
            episodeCount: parsedEp,
          ));
        }
      }
      seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      return seasons;
    }
  }

  Future<List<EpisodeItem>> getEpisodes(String subjectId, int seasonNumber) async {
    if (useGateway) {
      final res = await _requestGateway("/titles/$subjectId/episodes", params: {
        "season": seasonNumber,
        "start": 1,
        "end": 100,
      });
      final list = res["data"]?["episodes"] as List? ?? [];
      final eps = list.map((e) => EpisodeItem(
        episodeNumber: e["episode"] ?? e["ep"] ?? 1,
        seasonNumber: seasonNumber,
        title: e["title"] ?? "Episode ${e['episode'] ?? e['ep'] ?? 1}",
        description: e["desc"] ?? "",
      )).toList();
      eps.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return eps;
    } else {
      final res = await _requestDirect("GET", "/wefeed-mobile-bff/subject-api/season-info", params: {
        "host": defaultApiHost,
        "subjectId": subjectId,
        "se": seasonNumber.toString(),
        "startPosition": "1",
        "endPosition": "100",
        "pagerMode": "1",
      });
      final List<EpisodeItem> episodes = [];
      final list = res["data"]?["episodes"] as List? ?? [];
      for (var e in list) {
        final epNum = e["episode"] ?? e["ep"] ?? 1;
        episodes.add(EpisodeItem(
          episodeNumber: epNum is int ? epNum : int.tryParse(epNum.toString()) ?? 1,
          seasonNumber: seasonNumber,
          title: e["title"]?.toString() ?? "Episode $epNum",
          description: e["desc"]?.toString() ?? "",
        ));
      }
      // If episodes list is empty, generate from maxEp count in seasons
      if (episodes.isEmpty) {
        final seasons = res["data"]?["seasons"] as List? ?? [];
        for (var s in seasons) {
          final seNum = s["se"] ?? s["season"];
          if (seNum == seasonNumber) {
            final maxEp = s["maxEp"] ?? s["maxEpisode"] ?? 1;
            final count = maxEp is int ? maxEp : int.tryParse(maxEp.toString()) ?? 1;
            for (var i = 1; i <= count; i++) {
              episodes.add(EpisodeItem(
                episodeNumber: i,
                seasonNumber: seasonNumber,
                title: "Episode $i",
                description: "",
              ));
            }
            break;
          }
        }
      }
      episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return episodes;
    }
  }

  Future<List<StreamOption>> getStreams(String subjectId, {int season = 0, int episode = 0}) async {
    if (useGateway) {
      final res = await _requestGateway("/titles/$subjectId/stream", params: {
        "season": season,
        "episode": episode,
      });
      final List<StreamOption> streams = [];
      final sel = res["selected"];
      if (sel != null && sel["url"] != null && sel["url"].toString().isNotEmpty) {
        final u = sel["url"].toString();
        streams.add(StreamOption(
          url: u,
          kind: guessMediaKind(u, sel["kind"]?.toString()),
          resolution: sel["max_resolution"] ?? "1080p",
          sizeMb: (sel["size_mb"] as num?)?.toDouble(),
          durationSeconds: sel["duration_seconds"],
          cookie: sel["cookie"],
          bypassedDecoy: sel["bypassed_decoy"] ?? false,
        ));
      }
      final alts = res["alternatives"] as List? ?? [];
      for (var alt in alts) {
        if (alt is Map && alt["url"] != null && alt["url"].toString().isNotEmpty && alt["url"] != sel?["url"]) {
          final u = alt["url"].toString();
          streams.add(StreamOption(
            url: u,
            kind: guessMediaKind(u, alt["kind"]?.toString()),
            resolution: alt["max_resolution"] ?? (alt["resolutions"] != null ? "${alt['resolutions']}p" : "720p"),
            sizeMb: (alt["size_mb"] as num?)?.toDouble(),
            durationSeconds: alt["duration_seconds"],
            cookie: alt["cookie"],
            bypassedDecoy: alt["bypassed_decoy"] ?? false,
          ));
        }
      }
      return streams;
    } else {
      var res = await _requestDirect("GET", "/wefeed-mobile-bff/subject-api/play-info", params: {
        "host": defaultApiHost,
        "subjectId": subjectId,
        "se": season.toString(),
        "ep": episode.toString(),
      });

      var rawStreams = res["data"]?["streams"] as List? ?? [];

      // Auto-retry with refreshed session token if empty and response indicated error or empty data
      if (rawStreams.isEmpty && (res["code"] != 0 || res["data"] == null)) {
        try {
          _sessionToken = null;
          await _bootstrapSession(force: true);
          res = await _requestDirectRaw("GET", "/wefeed-mobile-bff/subject-api/play-info", params: {
            "host": defaultApiHost,
            "subjectId": subjectId,
            "se": season.toString(),
            "ep": episode.toString(),
          });
          rawStreams = res["data"]?["streams"] as List? ?? [];
        } catch (_) {}
      }

      // Fallback 1: If season == 0 returned 0 streams, try season = 1
      if (rawStreams.isEmpty && season == 0) {
        try {
          final fbRes = await _requestDirectRaw("GET", "/wefeed-mobile-bff/subject-api/play-info", params: {
            "host": defaultApiHost,
            "subjectId": subjectId,
            "se": "1",
            "ep": episode == 0 ? "1" : episode.toString(),
          });
          final fbStreams = fbRes["data"]?["streams"] as List? ?? [];
          if (fbStreams.isNotEmpty) {
            rawStreams = fbStreams;
          }
        } catch (_) {}
      }

      // Fallback 2: If season > 0 and episode == 0 returned 0 streams, try episode = 1
      if (rawStreams.isEmpty && season > 0 && episode == 0) {
        try {
          final fbRes = await _requestDirectRaw("GET", "/wefeed-mobile-bff/subject-api/play-info", params: {
            "host": defaultApiHost,
            "subjectId": subjectId,
            "se": season.toString(),
            "ep": "1",
          });
          final fbStreams = fbRes["data"]?["streams"] as List? ?? [];
          if (fbStreams.isNotEmpty) {
            rawStreams = fbStreams;
          }
        } catch (_) {}
      }

      final List<StreamOption> streams = [];
      final seenUrls = <String>{};

      for (var s in rawStreams) {
        final rawUrl = s["url"]?.toString() ?? "";
        final signCookie = s["signCookie"]?.toString();
        final realTuple = extractRealStreamFromCookie(signCookie);

        String effectiveUrl = rawUrl;
        String effectiveKind = (s["format"] ?? "mp4").toString().toLowerCase();
        bool isDecoyBypassed = false;
        final isDecoy = isDecoyUrl(rawUrl);

        if (realTuple != null && (isDecoy || rawUrl.isEmpty || rawUrl.contains("aoneroom.com/other"))) {
          effectiveUrl = realTuple[0];
          effectiveKind = realTuple[1];
          isDecoyBypassed = true;
        } else if (isDecoy) {
          // Strict: drop unbypassed decoy update videos completely
          continue;
        } else {
          final fmt = (s["format"] ?? "").toString().toUpperCase();
          effectiveKind = fmt == "DASH"
              ? "dash"
              : (fmt == "HLS" ? "hls" : (realTuple != null ? realTuple[1] : fmt.toLowerCase()));
        }

        if (effectiveUrl.isEmpty || seenUrls.contains(effectiveUrl)) continue;
        if (isDecoy && !isDecoyBypassed) continue;

        seenUrls.add(effectiveUrl);

        var resStr = s["resolutions"]?.toString() ?? s["resolution"]?.toString() ?? "720";
        if (resStr.contains(",")) {
          final list = resStr.split(",").map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          if (list.isNotEmpty) {
            resStr = list.first;
          }
        }
        if (!resStr.endsWith("p") && int.tryParse(resStr) != null) {
          resStr = "${resStr}p";
        }

        final sizeVal = s["size"];
        final sizeMb = sizeVal != null ? (double.tryParse(sizeVal.toString()) ?? 0) / 1e6 : null;

        streams.add(StreamOption(
          url: effectiveUrl,
          kind: effectiveKind,
          resolution: resStr,
          sizeMb: sizeMb != null ? double.parse(sizeMb.toStringAsFixed(1)) : null,
          durationSeconds: s["duration"] as int?,
          cookie: signCookie != null ? _cleanCookie(signCookie) : null,
          bypassedDecoy: isDecoyBypassed,
        ));
      }

      // Fallback 3: If no valid streams found from play-info, query the /resource endpoint
      if (streams.isEmpty) {
        try {
          final resObj = await _requestDirectRaw("GET", "/wefeed-mobile-bff/subject-api/resource", params: {
            "host": defaultApiHost,
            "subjectId": subjectId,
            "se": season.toString(),
            "ep": episode.toString(),
          });
          final list = resObj["data"]?["list"] as List? ?? [];
          for (var item in list) {
            String link = item["resourceLink"]?.toString() ?? "";
            if (!isValidMediaUrl(link)) {
              final dl = item["downloadUrl"]?.toString() ?? "";
              if (isValidMediaUrl(dl)) {
                link = dl;
              } else {
                continue;
              }
            }
            if (isValidMediaUrl(link) && !seenUrls.contains(link)) {
              seenUrls.add(link);
              final resNum = item["resolution"]?.toString() ?? "720";
              final resStr = resNum.endsWith("p") ? resNum : "${resNum}p";
              final sizeVal = item["size"];
              final sizeMb = sizeVal != null ? (double.tryParse(sizeVal.toString()) ?? 0) / 1e6 : null;
              streams.add(StreamOption(
                url: link,
                kind: link.contains(".m3u8") ? "hls" : (link.contains(".mpd") ? "dash" : "mp4"),
                resolution: resStr,
                sizeMb: sizeMb != null ? double.parse(sizeMb.toStringAsFixed(1)) : null,
                durationSeconds: item["duration"] as int?,
                bypassedDecoy: true,
              ));
            }
          }
        } catch (_) {}
      }

      // Fallback 4: Query /subject-api/get resourceDetectors for direct signed streams
      if (streams.isEmpty) {
        try {
          final getObj = await _requestDirectRaw("GET", "/wefeed-mobile-bff/subject-api/get", params: {
            "host": defaultApiHost,
            "subjectId": subjectId,
          });
          final data = getObj["data"] as Map<String, dynamic>?;
          final detectors = data?["resourceDetectors"] as List? ?? [];
          for (var detector in detectors) {
            if (detector is Map) {
              final resList = detector["resolutionList"] as List? ?? [];
              for (var resItem in resList) {
                if (resItem is Map) {
                  final itemLink = resItem["resourceLink"]?.toString() ?? resItem["downloadUrl"]?.toString() ?? "";
                  if (isValidMediaUrl(itemLink) && !seenUrls.contains(itemLink)) {
                    seenUrls.add(itemLink);
                    final resVal = resItem["resolution"]?.toString() ?? "720";
                    final resStr = resVal.endsWith("p") ? resVal : "${resVal}p";
                    final sizeVal = resItem["size"];
                    final sizeMb = sizeVal != null ? (double.tryParse(sizeVal.toString()) ?? 0) / 1e6 : null;
                    streams.add(StreamOption(
                      url: itemLink,
                      kind: itemLink.contains(".m3u8") ? "hls" : (itemLink.contains(".mpd") ? "dash" : "mp4"),
                      resolution: resStr,
                      sizeMb: sizeMb != null ? double.parse(sizeMb.toStringAsFixed(1)) : null,
                      durationSeconds: resItem["duration"] as int?,
                      bypassedDecoy: true,
                    ));
                  }
                }
              }

              // Fallback to detector-level downloadUrl or resourceLink if resolutionList was empty
              final detLink = detector["downloadUrl"]?.toString() ?? detector["resourceLink"]?.toString() ?? "";
              if (isValidMediaUrl(detLink) && !seenUrls.contains(detLink)) {
                seenUrls.add(detLink);
                final sizeVal = detector["firstSize"] ?? detector["totalSize"];
                final sizeMb = sizeVal != null ? (double.tryParse(sizeVal.toString()) ?? 0) / 1e6 : null;
                streams.add(StreamOption(
                  url: detLink,
                  kind: detLink.contains(".m3u8") ? "hls" : (detLink.contains(".mpd") ? "dash" : "mp4"),
                  resolution: "720p",
                  sizeMb: sizeMb != null ? double.parse(sizeMb.toStringAsFixed(1)) : null,
                  bypassedDecoy: true,
                ));
              }
            }
          }
        } catch (_) {}
      }

      // Final strict filter: remove any remaining decoy honeypot URLs or invalid non-media URLs
      streams.removeWhere((st) => (!isValidMediaUrl(st.url) && !st.bypassedDecoy) || (isDecoyUrl(st.url) && !st.bypassedDecoy));

      // Sort streams: highest resolution first (1080p > 720p > 480p)
      streams.sort((a, b) {
        final aNum = int.tryParse(a.resolution.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bNum = int.tryParse(b.resolution.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return bNum.compareTo(aNum);
      });

      return streams;
    }
  }

  String? _cleanCookie(String raw) {
    final parts = raw.split(";").map((p) => p.trim()).where((p) => p.isNotEmpty);
    return parts.isNotEmpty ? parts.join("; ") : null;
  }

  static bool isDecoyUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final u = url.toLowerCase();
    // Upstream honeypot / decoy update announcement video patterns
    if (u.contains("b164fbfb4347792950bdfbfb563d39d9") ||
        u.contains("80da52722ee7de7a4303290af6783424") ||
        u.contains("macdn.aoneroom.com") ||
        u.contains("aoneroom.com/other") ||
        u.contains("/other/") ||
        u.contains("/upgrade/") ||
        u.contains("/notice/") ||
        u.contains("dummy") ||
        u.contains("decoy") ||
        u.contains("update_app") ||
        u.contains("app_update") ||
        RegExp(r'/other/(\d{4}/\d{2}/\d{2}/|.*\.mp4)', caseSensitive: false).hasMatch(u)) {
      return true;
    }
    // Any direct .mp4 video served from aoneroom.com domain is an update honeypot notice
    if (u.contains("aoneroom.com") && (u.endsWith(".mp4") || u.contains(".mp4?"))) {
      return true;
    }
    return false;
  }

  static bool isValidMediaUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    if (isDecoyUrl(url)) return false;
    final lower = url.toLowerCase();
    if (lower.contains("ailok.pe") || lower.contains("/info/")) return false;
    if (!lower.startsWith("http://") && !lower.startsWith("https://")) return false;
    final hasMediaExt = lower.contains(".mp4") ||
        lower.contains(".m3u8") ||
        lower.contains(".mpd") ||
        lower.contains(".m4s") ||
        lower.contains(".mkv");
    final hasCdnHost = lower.contains("aoneroom.com") ||
        lower.contains("hakunaymatata.com") ||
        lower.contains("akamaized.net") ||
        lower.contains("aliyuncs.com") ||
        lower.contains("cloudcdn.net") ||
        lower.contains("cloudfront.net");
    return hasMediaExt || hasCdnHost;
  }

  static String guessMediaKind(String url, [String? fallbackKind]) {
    final lower = url.toLowerCase();
    if (lower.contains(".m3u8")) return "hls";
    if (lower.contains(".mpd")) return "dash";
    if (lower.contains(".mp4") || lower.contains(".m4v") || lower.contains(".m4a")) return "mp4";
    final f = fallbackKind?.toLowerCase();
    if (f == "dash" || f == "hls" || f == "mp4") return f!;
    return "mp4";
  }

  static String decodeB64(String b64, {bool isCloudFront = false}) {
    var s = b64.trim();
    if (isCloudFront) {
      s = s.replaceAll("-", "+").replaceAll("~", "/").replaceAll("_", "=");
    } else {
      s = s.replaceAll("-", "+").replaceAll("~", "/").replaceAll("_", "/");
    }
    while (s.length % 4 != 0) {
      s += "=";
    }
    return utf8.decode(base64.decode(s), allowMalformed: true);
  }

  static List<String>? extractRealStreamFromCookie(String? cookie) {
    if (cookie == null || cookie.isEmpty) return null;
    final parts = cookie.split(";");
    for (var part in parts) {
      final trimmed = part.trim();
      // 1. CloudFront Signed Cookies
      if (trimmed.startsWith("CloudFront-Policy=")) {
        final b64 = trimmed.substring("CloudFront-Policy=".length);
        try {
          final decoded = decodeB64(b64, isCloudFront: true);
          final resMatch = RegExp(r'"Resource"\s*:\s*"([^"]+)"').firstMatch(decoded);
          if (resMatch != null) {
            final rawResource = resMatch.group(1)!;
            final baseResource = rawResource.endsWith("*")
                ? rawResource.substring(0, rawResource.length - 1)
                : rawResource;
            if (baseResource.contains("/hls/") || baseResource.contains(".m3u8")) {
              return [
                baseResource.endsWith(".m3u8") ? baseResource : "${baseResource}local.m3u8",
                "hls"
              ];
            } else if (baseResource.contains("/dash/") || baseResource.contains(".mpd")) {
              return [
                baseResource.endsWith(".mpd") ? baseResource : "${baseResource}index_web.mpd",
                "dash"
              ];
            } else if (baseResource.contains(".mp4")) {
              return [baseResource, "mp4"];
            }
            return [baseResource, guessMediaKind(baseResource)];
          }
        } catch (_) {}
      }

      // 2. Edge Cache Cookies (urlprefix=<base64 url prefix>)
      if (trimmed.contains("Edge-Cache-Cookie") || trimmed.contains("urlprefix=")) {
        final subparts = trimmed.contains(":") ? trimmed.split(":") : [trimmed];
        for (var sub in subparts) {
          final sTrim = sub.trim();
          if (sTrim.contains("urlprefix=")) {
            final b64 = sTrim.split("urlprefix=")[1].trim();
            try {
              final prefix = decodeB64(b64).trim();
              if (prefix.startsWith("http://") || prefix.startsWith("https://")) {
                if (prefix.contains("/hls/") || prefix.contains(".m3u8")) {
                  final fixed = prefix.endsWith(".m3u8")
                      ? prefix
                      : (prefix.endsWith("/") ? "${prefix}local.m3u8" : "$prefix/local.m3u8");
                  return [fixed, "hls"];
                } else if (prefix.contains("/dash/") || prefix.contains(".mpd")) {
                  final fixed = prefix.endsWith(".mpd")
                      ? prefix
                      : (prefix.endsWith("/") ? "${prefix}index_web.mpd" : "$prefix/index_web.mpd");
                  return [fixed, "dash"];
                } else if (prefix.contains(".mp4")) {
                  return [prefix, "mp4"];
                }
                return [prefix, guessMediaKind(prefix)];
              }
            } catch (_) {}
          }
        }
      }
    }
    return null;
  }
}
