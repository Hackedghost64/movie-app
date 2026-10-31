import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbx_app/services/local_stream_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer mockUpstreamServer;
  late int mockPort;

  setUpAll(() async {
    HttpOverrides.global = null;
    // Start a mock upstream server simulating MovieBox CDN
    mockUpstreamServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mockPort = mockUpstreamServer.port;

    mockUpstreamServer.listen((HttpRequest request) async {
      final path = request.uri.path;
      if (path.endsWith('.mpd')) {
        request.response.headers.contentType = ContentType('application', 'dash+xml');
        request.response.write('''<?xml version="1.0" encoding="utf-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" minBufferTime="PT12.1S" mediaPresentationDuration="PT5000S">
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="1080p" bandwidth="2500000">
        <Initialization sourceURL="chunk-stream0-init.m4s"/>
        <SegmentURL media="chunk-stream0-00001.m4s"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''');
        await request.response.close();
      } else if (path.endsWith('.m4s')) {
        // Binary media chunk
        request.response.headers.contentType = ContentType('video', 'iso.segment');
        // Raw binary bytes
        final fakeVideoBytes = List<int>.generate(256, (i) => (i * 7) % 256);
        request.response.add(fakeVideoBytes);
        await request.response.close();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });

    await LocalStreamRelay.instance.start();
  });

  tearDownAll(() async {
    LocalStreamRelay.instance.stop();
    await mockUpstreamServer.close(force: true);
  });

  test('LocalStreamRelay generates valid relay URLs', () {
    final relayUrl = LocalStreamRelay.instance.getRelayUrl(
      url: 'http://127.0.0.1:$mockPort/movies/123/index_web.mpd',
      cookie: 'Edge-Cache-Cookie=urlprefix%3DaHR0cHM6Ly9leGFtcGxlLmNvbQ==',
      kind: 'dash',
      title: 'Test Movie',
    );

    expect(relayUrl, contains('http://127.0.0.1:'));
    expect(relayUrl, contains('/relay/'));
    expect(relayUrl, endsWith('/index_web.mpd'));
  });

  test('LocalStreamRelay optimizes MPD minBufferTime to PT1.5S without corrupting XML', () async {
    final relayUrl = LocalStreamRelay.instance.getRelayUrl(
      url: 'http://127.0.0.1:$mockPort/movies/123/index_web.mpd',
      cookie: 'Edge-Cache-Cookie=test',
      kind: 'dash',
    );

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(relayUrl));
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.ok);
    expect(resp.headers.contentType.toString(), contains('application/dash+xml'));

    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('minBufferTime="PT1.5S"'));
    expect(body, isNot(contains('minBufferTime="PT12.1S"')));
    client.close();
  });

  test('LocalStreamRelay proxies binary .m4s media segments without corrupting binary data', () async {
    final relayUrl = LocalStreamRelay.instance.getRelayUrl(
      url: 'http://127.0.0.1:$mockPort/movies/123/index_web.mpd',
      cookie: 'Edge-Cache-Cookie=test',
      kind: 'dash',
    );

    // Form segment URL by resolving against manifest URL
    final segmentRelayUrl = relayUrl.replaceFirst('index_web.mpd', 'chunk-stream0-00001.m4s');

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(segmentRelayUrl));
    final resp = await req.close();
    expect(resp.statusCode, HttpStatus.ok);

    final receivedBytes = await resp.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
    final expectedBytes = List<int>.generate(256, (i) => (i * 7) % 256);

    expect(receivedBytes, equals(expectedBytes));
    client.close();
  });
}
