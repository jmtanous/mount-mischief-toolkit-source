import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mount_mischief_toolkit/catalog.dart';
import 'package:mount_mischief_toolkit/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('toolkit-catalog-');
    FlutterSecureStorage.setMockInitialValues({'github_token': 'test-token'});
  });
  tearDown(() => temp.deleteSync(recursive: true));
  test('Fresh install extracts and verifies bundled Pilot without any network request', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((request) async {
        fail('Bundled installation attempted network access: ${request.url}');
      }),
    );
    final seed = (await client.cached()).single;
    final archive = await client.download(seed, (_, _) {});
    expect(await archive.length(), seed.bytes);
    expect(await client.available(seed), isTrue);
    expect((await client.bootstrap()).path, archive.path);
    client.close();
  });
  test(
    'Damaged catalog metadata falls back offline and preserves package files',
    () async {
      final client = Catalog(cacheDirectory: temp);
      final seed = (await client.cached()).first;
      final file = File('${(await client.directory).path}/catalog.json');
      final package = await client.path(seed);
      await package.writeAsString('existing package bytes');
      for (final damaged in [
        '{',
        '{"schema":99,"projects":[]}',
        '{"schema":1,"projects":[null]}',
        jsonEncode({
          'schema': 1,
          'projects': [
            {
              ...seed.json,
              'devices': ['other-device'],
            },
          ],
        }),
        jsonEncode({
          'schema': 1,
          'projects': [
            {...seed.json, 'resources': []},
          ],
        }),
      ]) {
        await file.writeAsString(damaged);
        final fallback = await client.cached();
        expect(fallback.single.hash, seed.hash);
        expect(client.cacheNotice, contains('Showing the bundled project'));
        expect(await package.readAsString(), 'existing package bytes');
        expect(await file.readAsString(), damaged);
      }
      await file.writeAsString(
        jsonEncode({
          'schema': 1,
          'projects': [seed.json],
        }),
      );
      await client.cached();
      expect(client.cacheNotice, isNull);
      client.close();
    },
  );
  test(
    'Malformed saved authorization does not block offline catalog access',
    () async {
      for (final value in [
        '{',
        '[]',
        '{"access_token":42}',
        '{"access_token":"test","expires_at":"invalid"}',
      ]) {
        FlutterSecureStorage.setMockInitialValues({'github_session': value});
        final client = Catalog(cacheDirectory: temp);
        expect((await client.cached()).single.id, 'alpaca-pilot');
        expect(await client.storage.read(key: 'github_session'), isNull);
        client.close();
      }
    },
  );
  test(
    'Duplicate project versions cannot replace a valid saved catalog',
    () async {
      final seed = jsonDecode(
        File('assets/catalog.json').readAsStringSync(),
      )['projects'][0];
      final content = jsonEncode({
        'schema': 1,
        'projects': [
          seed,
          {...seed as Map, 'sha256': '0' * 64},
        ],
      });
      final client = Catalog(
        cacheDirectory: temp,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'content': base64.encode(utf8.encode(content))}),
            200,
          ),
        ),
      );
      final saved = File('${(await client.directory).path}/catalog.json');
      final original = jsonEncode({
        'schema': 1,
        'projects': [seed],
      });
      await saved.writeAsString(original);
      await expectLater(client.refresh(), throwsFormatException);
      expect(await saved.readAsString(), original);
      expect(
        client.decodeCatalog(
          jsonEncode({
            'schema': 1,
            'projects': [
              seed,
              {...seed, 'version': 'next-version'},
            ],
          }),
        ),
        hasLength(2),
      );
      client.close();
    },
  );
  for (final status in [401, 403, 404, 429, 503]) {
    test(
      'Catalog $status preserves cached data without requiring an account',
      () async {
        final client = Catalog(
          cacheDirectory: temp,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.headers.containsKey('Authorization'), isFalse);
            return http.Response(
              '',
              status,
              headers: {'x-ratelimit-remaining': '0'},
            );
          }),
        );
        final before = await client.cached();
        await expectLater(
          client.refresh(),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'message',
              allOf(contains('cached'), isNot(contains('Sign in'))),
            ),
          ),
        );
        expect((await client.cached()).single.hash, before.single.hash);
        client.close();
      },
    );
  }

  test(
    'Migration deletes only retired GitHub credentials and preserves pairing',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'github_session': '{"access_token":"old-token"}',
        'github_token': 'old-token',
        'ssh_identity_fixture': 'keep',
      });
      final client = Catalog(cacheDirectory: temp);
      final seed = (await client.cached()).single;
      final file = await client.path(seed);
      await file.writeAsString('keep package');
      await client.cached();
      expect(await client.storage.read(key: 'github_session'), isNull);
      expect(await client.storage.read(key: 'github_token'), isNull);
      expect(await client.storage.read(key: 'ssh_identity_fixture'), 'keep');
      expect(await file.readAsString(), 'keep package');
      client.close();
    },
  );

  test('Public catalog refresh works on a fresh install with no credentials', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final content = File('assets/catalog.json').readAsStringSync();
    var requests = 0;
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/repos/jmtanous/mount-mischief-toolkit-source/contents/catalog.json',
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode({'content': base64.encode(utf8.encode(content))}),
          200,
        );
      }),
    );
    expect((await client.refresh()).single.id, 'alpaca-pilot');
    expect(
      await File('${(await client.directory).path}/catalog.json')
          .readAsString(),
      content,
    );
    expect(requests, 1);
    client.close();
  });

  test('Offline refresh retains saved catalog and verified package', () async {
    final payload = utf8.encode('cached archive');
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    final seed = (await client.cached()).single;
    final manifest = ProjectManifest({
      ...seed.json,
      'sha256': sha256.convert(payload).toString(),
      'archive_bytes': payload.length,
    });
    await (await client.path(manifest)).writeAsBytes(payload);
    final saved = jsonEncode({
      'schema': 1,
      'projects': [manifest.json],
    });
    await File('${(await client.directory).path}/catalog.json')
        .writeAsString(saved);
    await expectLater(
      client.refresh(),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('Check internet'),
        ),
      ),
    );
    expect((await client.cached()).single.hash, manifest.hash);
    expect(await client.download(manifest, (_, _) {}), isA<File>());
    expect(await client.available(manifest), isTrue);
    client.close();
  });

  test('Malformed catalog does not replace cached data', () async {
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'content': base64.encode(
              utf8.encode('{"schema":99,"projects":[]}'),
            ),
          }),
          200,
        ),
      ),
    );
    await expectLater(client.refresh(), throwsFormatException);
    expect((await client.cached()).first.id, 'alpaca-pilot');
    client.close();
  });
  test('Invalid project digest is rejected', () {
    expect(
      () => ProjectManifest({'schema': 1, 'id': 'test', 'sha256': 'wrong'}),
      throwsFormatException,
    );
  });
  test('Asset redirect never forwards GitHub credentials', () async {
    final payload = utf8.encode('package');
    var requests = 0;
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((request) async {
        requests++;
        if (request.url.host == 'api.github.com') {
          expect(request.headers.containsKey('Authorization'), isFalse);
          expect(request.method, 'GET');
          return http.Response(
            '',
            302,
            headers: {
              'location': 'https://release-assets.githubusercontent.com/asset',
            },
          );
        }
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response.bytes(payload, 200);
      }),
    );
    final seed = (await client.cached()).first;
    final manifest = ProjectManifest({
      ...seed.json,
      'asset_id': 123,
      'sha256': sha256.convert(payload).toString(),
      'archive_bytes': payload.length,
    });
    final file = await client.download(manifest, (_, _) {});
    expect(await file.readAsBytes(), payload);
    expect(requests, 2);
    expect(await client.available(manifest), isTrue);
    client.close();
  });
  test('Corrupt asset is discarded without replacing cached package', () async {
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient(
        (request) async => http.Response.bytes([1, 2, 3], 200),
      ),
    );
    final seed = (await client.cached()).first;
    final manifest = ProjectManifest({
      ...seed.json,
      'asset_id': 123,
      'sha256': '0' * 64,
      'archive_bytes': 3,
    });
    await expectLater(client.download(manifest, (_, _) {}), throwsStateError);
    expect(await client.available(manifest), isFalse);
    expect(
      File('${(await client.path(manifest)).path}.part').existsSync(),
      isFalse,
    );
    client.close();
  });

  test('Redirect discards a never-ending body and strips credentials on port change', () async {
    var cancelledBody = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelledBody = true;
      },
    );
    final payload = utf8.encode('archive');
    var requests = 0;
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient.streaming((request, _) async {
        requests++;
        if (requests == 1) {
          return http.StreamedResponse(
            body.stream,
            302,
            headers: {'location': 'https://api.github.com:444/asset'},
          );
        }
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.StreamedResponse(Stream.value(payload), 200);
      }),
    );
    final seed = (await client.cached()).first;
    final manifest = ProjectManifest({
      ...seed.json,
      'asset_id': 1,
      'sha256': sha256.convert(payload).toString(),
      'archive_bytes': payload.length,
    });
    await client
        .download(manifest, (_, _) {})
        .timeout(const Duration(seconds: 2));
    expect(cancelledBody, isTrue);
    expect(requests, 2);
    await body.close();
    client.close();
  });

  for (final mode in ['connection-loss', 'oversize', 'short-body']) {
    test(
      'Failed $mode download removes partial data and preserves previous cache',
      () async {
        Stream<List<int>> response() async* {
          yield [1, 2, 3];
          if (mode == 'connection-loss') throw const SocketException('offline');
          if (mode == 'oversize') yield List.filled(10, 0);
        }

        final client = Catalog(
          cacheDirectory: temp,
          client: MockClient.streaming(
            (_, _) async => http.StreamedResponse(response(), 200),
          ),
        );
        final seed = (await client.cached()).first;
        final manifest = ProjectManifest({
          ...seed.json,
          'asset_id': 1,
          'sha256': '0' * 64,
          'archive_bytes': 6,
        });
        final previous = await client.path(manifest);
        await previous.writeAsString('old');
        await expectLater(
          client.download(manifest, (_, _) {}),
          mode == 'connection-loss'
              ? throwsA(isA<SocketException>())
              : throwsStateError,
        );
        expect(await previous.readAsString(), 'old');
        expect(await File('${previous.path}.part').exists(), isFalse);
        client.close();
      },
    );
  }

  test('Unavailable public asset preserves the cached catalog', () async {
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((_) async => http.Response('', 404)),
    );
    final seed = (await client.cached()).single;
    await expectLater(
      client.download(
        ProjectManifest({...seed.json, 'asset_id': 1}),
        (_, _) {},
      ),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('not available for public download'),
        ),
      ),
    );
    expect((await client.cached()).single.hash, seed.hash);
    client.close();
  });

  for (final redirect in [
    'http://example.com/package',
    'https://user:password@example.com/package',
  ]) {
    test('Reject unsafe public download redirect $redirect', () async {
      final client = Catalog(
        cacheDirectory: temp,
        client: MockClient(
          (_) async => http.Response('', 302, headers: {'location': redirect}),
        ),
      );
      final seed = (await client.cached()).single;
      await expectLater(
        client.download(
          ProjectManifest({...seed.json, 'asset_id': 1}),
          (_, _) {},
        ),
        throwsStateError,
      );
      client.close();
    });
  }
}
