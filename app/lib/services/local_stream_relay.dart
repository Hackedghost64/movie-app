import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'moviebox_api.dart';

class LocalStreamRelay {
  static final LocalStreamRelay instance = LocalStreamRelay._();
  LocalStreamRelay._();

  HttpServer? _server;
  int _port = 0;
  final Map<String, _RelayItem> _registry = {};

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30)
    ..badCertificateCallback = ((cert, host, port) => true);

  Completer<void>? _initCompleter;

  int get port => _port;
  bool get isRunning => _server != null && _port != 0;

  Future<void> ensureStarted() async {
    if (_server != null && _port != 0) return;
    try {
      await start();
    } catch (_) {}
  }

  Future<void> start() async {
    if (_server != null && _port != 0) return;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<void>();
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('LocalStreamRelay server error: $e');
      });
      debugPrint('LocalStreamRelay listening on http://127.0.0.1:$_port');
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('LocalStreamRelay start error: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null;
    }
  }

  /// Registers a stream and returns a local proxy URL ready for VLC, MPV, or internal player.
  String getRelayUrl({
    required String url,
    String? cookie,
    String? kind,
    String? title,
  }) {
    if (_server == null || _port == 0) {
      // In case server hasn't started yet, trigger async start
      start();
    }

    if (_port == 0) {
      // If server could not bind or hasn't finished starting, gracefully fallback to direct url
      return url;
    }

    final id = (url.hashCode ^ (cookie?.hashCode ?? 0)).abs().toString();
    final uri = Uri.parse(url);
    final baseUrl = url.substring(0, url.lastIndexOf('/') + 1);

    final validSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    var fileName = validSegments.isNotEmpty ? validSegments.last : 'media.mp4';
    final effectiveKind = kind ?? (url.contains('.m3u8') ? 'hls' : (url.contains('.mpd') ? 'dash' : 'mp4'));
    if (effectiveKind == 'dash' && !fileName.endsWith('.mpd') && !fileName.contains('.')) {
      fileName = '$fileName.mpd';
    } else if (effectiveKind == 'hls' && !fileName.endsWith('.m3u8') && !fileName.contains('.')) {
      fileName = '$fileName.m3u8';
    }

    _registry[id] = _RelayItem(
      originalUrl: url,
      baseUrl: baseUrl,
      cookie: cookie,
      kind: effectiveKind,
      title: title,
      fileName: fileName,
    );

    return 'http://127.0.0.1:$_port/relay/$id/$fileName';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      final pathSegments = request.uri.pathSegments;
      if (pathSegments.length < 3 || pathSegments[0] != 'relay') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final id = pathSegments[1];
      final item = _registry[id];
      if (item == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final subPath = pathSegments.sublist(2).join('/');
      String targetUrl;
      final originalUri = Uri.parse(item.originalUrl);
      final validOriginalSegments = originalUri.pathSegments.where((s) => s.isNotEmpty).toList();
      final originalLastSegment = validOriginalSegments.isNotEmpty ? validOriginalSegments.last : '';

      if (subPath == originalLastSegment || subPath == item.fileName || subPath.isEmpty || subPath.startsWith('media.')) {
        targetUrl = item.originalUrl;
      } else {
        targetUrl = '${item.baseUrl}$subPath';
        if (request.uri.hasQuery && request.uri.query.isNotEmpty) {
          targetUrl = '$targetUrl?${request.uri.query}';
        } else if (originalUri.hasQuery && originalUri.query.isNotEmpty) {
          targetUrl = '$targetUrl?${originalUri.query}';
        }
      }

      final upstreamReq = await _httpClient.getUrl(Uri.parse(targetUrl));
      
      // Forward incoming headers
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }

      // Inject authentication cookies and headers
      if (item.cookie != null && item.cookie!.isNotEmpty) {
        upstreamReq.headers.set(HttpHeaders.cookieHeader, item.cookie!);
      }
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'MovieBox/${MovieBoxApi.appVersion} (Android 14; Pixel 8 Pro)',
      );

      final upstreamResp = await upstreamReq.close();
      response.statusCode = upstreamResp.statusCode;

      // Forward response headers
      for (var name in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ]) {
        final val = upstreamResp.headers.value(name);
        if (val != null) {
          response.headers.set(name, val);
        }
      }
      response.headers.set('Access-Control-Allow-Origin', '*');

      final cleanPath = Uri.parse(targetUrl).path.toLowerCase();
      final isMpdManifest = cleanPath.endsWith('.mpd');

      // Optimize DASH manifest for ultra-fast startup and seeking ONLY if it's the manifest itself
      if (isMpdManifest && upstreamResp.statusCode >= 200 && upstreamResp.statusCode < 300) {
        final bodyBytes = await upstreamResp.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        var mpdText = utf8.decode(bodyBytes, allowMalformed: true);
        // Reduce minBufferTime from e.g. 12.1s down to 1.5s for instant playback startup
        mpdText = mpdText.replaceAll(RegExp(r'minBufferTime="PT[0-9.]+S"'), 'minBufferTime="PT1.5S"');
        final modifiedBytes = utf8.encode(mpdText);
        response.headers.set(HttpHeaders.contentTypeHeader, 'application/dash+xml');
        response.headers.set(HttpHeaders.contentLengthHeader, modifiedBytes.length.toString());
        response.add(modifiedBytes);
        await response.close();
        return;
      }

      // Stream media chunks directly
      try {
        await response.addStream(upstreamResp);
        await response.close();
      } catch (_) {}
    } catch (e, stack) {
      debugPrint('LocalStreamRelay handle error: $e\n$stack');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
    _initCompleter = null;
  }
}

class _RelayItem {
  final String originalUrl;
  final String baseUrl;
  final String? cookie;
  final String kind;
  final String? title;
  final String? fileName;

  _RelayItem({
    required this.originalUrl,
    required this.baseUrl,
    this.cookie,
    required this.kind,
    this.title,
    this.fileName,
  });
}
