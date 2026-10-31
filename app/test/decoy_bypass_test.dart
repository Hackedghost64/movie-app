import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbx_app/services/moviebox_api.dart';

void main() {
  group('Decoy Video Detection & Cookie Bypass Tests', () {
    test('isDecoyUrl accurately identifies upstream decoy honeypots', () {
      expect(
        MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/other/2026/09/04/b164fbfb4347792950bdfbfb563d39d9.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/other/2026/10/10/80da52722ee7de7a4303290af6783424.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://example.com/other/test.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://example.com/other/2026/01/01/video.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://macdn.aoneroom.com/upgrade/notice.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://api6.aoneroom.com/static/update_app.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://media.aoneroom.com/video.mp4'),
        isTrue,
      );
      expect(
        MovieBoxApi.isDecoyUrl(''),
        isFalse,
      );
      expect(
        MovieBoxApi.isDecoyUrl(null),
        isFalse,
      );

      // Authentic streams should NOT be flagged as decoy
      expect(
        MovieBoxApi.isDecoyUrl('https://sbcdn5.hakunaymatata.com/hls/7845473610491125400-1-1-480-935/local.m3u8'),
        isFalse,
      );
      expect(
        MovieBoxApi.isDecoyUrl('https://sbcdn5.hakunaymatata.com/dash/7845473610491125400-1-1-1080-916/index_web.mpd'),
        isFalse,
      );
    });

    test('extractRealStreamFromCookie extracts authentic HLS stream from Edge-Cache-Cookie', () {
      const cookie =
          'Edge-Cache-Cookie=urlprefix=aHR0cHM6Ly9zYmNkbjUuaGFrdW5heW1hdGF0YS5jb20vaGxzLzc4NDU0NzM2MTA0OTExMjU0MDAtMS0xLTQ4MC05MzUv:sign=5132ddf1fe48d87865513d61c8ebfdbe:t=1790409219';
      final result = MovieBoxApi.extractRealStreamFromCookie(cookie);

      expect(result, isNotNull);
      expect(result![0], 'https://sbcdn5.hakunaymatata.com/hls/7845473610491125400-1-1-480-935/local.m3u8');
      expect(result[1], 'hls');
    });

    test('extractRealStreamFromCookie extracts authentic DASH stream from Edge-Cache-Cookie', () {
      final b64Dash = base64.encode(utf8.encode('https://sbcdn5.hakunaymatata.com/dash/12345/'));
      final cookie = 'Edge-Cache-Cookie=urlprefix=$b64Dash:sign=abc1234:t=99999999';
      final result = MovieBoxApi.extractRealStreamFromCookie(cookie);

      expect(result, isNotNull);
      expect(result![0], 'https://sbcdn5.hakunaymatata.com/dash/12345/index_web.mpd');
      expect(result[1], 'dash');
    });

    test('extractRealStreamFromCookie extracts stream from CloudFront-Policy', () {
      final policyJson = json.encode({
        "Statement": [
          {
            "Resource": "https://cf.example.com/hls/stream123/*",
            "Condition": {
              "DateLessThan": {"AWS:EpochTime": 1700000000}
            }
          }
        ]
      });
      final b64Policy = base64.encode(utf8.encode(policyJson)).replaceAll('+', '-').replaceAll('=', '_');
      final cookie = 'CloudFront-Policy=$b64Policy; CloudFront-Signature=abc; CloudFront-Key-Pair-Id=K123';
      final result = MovieBoxApi.extractRealStreamFromCookie(cookie);

      expect(result, isNotNull);
      expect(result![0], 'https://cf.example.com/hls/stream123/local.m3u8');
      expect(result[1], 'hls');
    });

    test('extractRealStreamFromCookie returns null on invalid or missing cookies', () {
      expect(MovieBoxApi.extractRealStreamFromCookie(null), isNull);
      expect(MovieBoxApi.extractRealStreamFromCookie(''), isNull);
      expect(MovieBoxApi.extractRealStreamFromCookie('session=12345'), isNull);
      expect(MovieBoxApi.extractRealStreamFromCookie('Edge-Cache-Cookie=foo=bar'), isNull);
    });

    test('isValidMediaUrl filters out unplayable info pages like ailok.pe and accepts genuine streams', () {
      // Reject bogus info links and non-media strings
      expect(MovieBoxApi.isValidMediaUrl('https://ailok.pe/info/The Amazing Spider-Man-57779-1080P-h265'), isFalse);
      expect(MovieBoxApi.isValidMediaUrl('https://ailok.pe/info/Spider-Man'), isFalse);
      expect(MovieBoxApi.isValidMediaUrl(''), isFalse);
      expect(MovieBoxApi.isValidMediaUrl(null), isFalse);
      expect(MovieBoxApi.isValidMediaUrl('https://macdn.aoneroom.com/other/2026/10/10/80da52722ee7de7a4303290af6783424.mp4'), isFalse);

      // Accept authentic video and CDN streams
      expect(MovieBoxApi.isValidMediaUrl('https://sbcdn5.hakunaymatata.com/dash/123/index_web.mpd'), isTrue);
      expect(MovieBoxApi.isValidMediaUrl('https://sbcdn5.hakunaymatata.com/hls/123/local.m3u8'), isTrue);
      expect(MovieBoxApi.isValidMediaUrl('https://bcdn.hakunaymatata.com/resource/h265/36ad4a42962a6bd8ba4984b2ddc4f5bb.mp4'), isTrue);
    });
  });
}
