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
        expect(await client.signedIn, isFalse);
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
  test('Catalog 401 clears credentials and keeps cached catalog', () async {
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((r) async => http.Response('', 401)),
    );
    final before = await client.cached();
    await expectLater(client.refresh(), throwsStateError);
    expect(await client.signedIn, isFalse);
    expect((await client.cached()).first.hash, before.first.hash);
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
  test('Missing OAuth registration gives actionable setup error', () async {
    final client = Catalog(cacheDirectory: temp, clientId: '');
    await expectLater(client.signIn((code, url) async {}), throwsStateError);
    client.close();
  });
  void expiredSession() {
    FlutterSecureStorage.setMockInitialValues({
      'github_session': jsonEncode({
        'access_token': 'expired-test-token',
        'refresh_token': 'test-refresh',
        'expires_at': 1,
      }),
    });
  }

  test('Concurrent requests rotate an expired token pair only once', () async {
    expiredSession();
    var requests = 0;
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = Catalog(
      client: MockClient((request) async {
        requests++;
        expect(
          request.url.toString(),
          'https://github.com/login/oauth/access_token',
        );
        expect(request.bodyFields, {
          'client_id': oauthClientId,
          'grant_type': 'refresh_token',
          'refresh_token': 'test-refresh',
        });
        started.complete();
        return response.future;
      }),
    );
    final first = client.headers();
    await started.future;
    final second = client.headers();
    response.complete(
      http.Response(
        jsonEncode({
          'access_token': 'rotated-token',
          'refresh_token': 'rotated-refresh',
          'expires_in': 28800,
        }),
        200,
      ),
    );
    for (final headers in await Future.wait([first, second])) {
      expect(headers['Authorization'], 'Bearer rotated-token');
    }
    expect((await client.headers())['Authorization'], 'Bearer rotated-token');
    expect(requests, 1);
    final stored = jsonDecode(
      (await client.storage.read(key: 'github_session'))!,
    );
    expect(stored['refresh_token'], 'rotated-refresh');
    client.close();
  });

  test('Rejected refresh clears the entire credential pair', () async {
    expiredSession();
    final client = Catalog(
      client: MockClient(
        (_) async => http.Response('{"error":"bad_refresh_token"}', 200),
      ),
    );
    await expectLater(client.headers(), throwsStateError);
    expect(await client.signedIn, isFalse);
    client.close();
  });

  test(
    'Transient refresh failure preserves the credential for retry',
    () async {
      expiredSession();
      final client = Catalog(
        client: MockClient((_) async => http.Response('', 503)),
      );
      await expectLater(client.headers(), throwsA(isA<HttpException>()));
      expect(await client.signedIn, isTrue);
      client.close();
    },
  );

  test('Sign out during renewal cannot restore credentials', () async {
    expiredSession();
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final client = Catalog(
      client: MockClient((_) async {
        started.complete();
        return response.future;
      }),
    );
    final pending = expectLater(client.headers(), throwsStateError);
    await started.future;
    await client.signOut();
    response.complete(http.Response('{"access_token":"late-token"}', 200));
    await pending;
    expect(await client.signedIn, isFalse);
    client.close();
  });
  test('OAuth honors pending and slow-down before storing token', () async {
    var polls = 0;
    final delays = <int>[];
    final client = Catalog(
      cacheDirectory: temp,
      clientId: 'registered-app',
      delay: (duration) async {
        delays.add(duration.inSeconds);
      },
      client: MockClient((request) async {
        if (request.url.path == '/login/device/code') {
          expect(request.bodyFields['scope'], 'repo');
          return http.Response(
            jsonEncode({
              'device_code': 'fake-code',
              'user_code': 'ABCD-EFGH',
              'verification_uri': 'https://github.com/login/device',
              'expires_in': 300,
              'interval': 5,
            }),
            200,
          );
        }
        polls++;
        return http.Response(
          jsonEncode(
            polls == 1
                ? {'error': 'authorization_pending'}
                : polls == 2
                ? {'error': 'slow_down'}
                : {'access_token': 'new-test-token'},
          ),
          200,
        );
      }),
    );
    await client.signIn((code, url) async {
      expect(code, 'ABCD-EFGH');
      expect(url.host, 'github.com');
    });
    expect(delays, [5, 5, 10]);
    expect((await client.headers())['Authorization'], 'Bearer new-test-token');
    client.close();
  });
  test('Denied OAuth does not store a new credential', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final client = Catalog(
      cacheDirectory: temp,
      clientId: 'registered-app',
      delay: (_) async {},
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path == '/login/device/code'
                ? {
                    'device_code': 'fake-code',
                    'user_code': 'CODE',
                    'verification_uri': 'https://github.com/login/device',
                    'expires_in': 300,
                    'interval': 5,
                  }
                : {'error': 'access_denied'},
          ),
          200,
        ),
      ),
    );
    await expectLater(client.signIn((code, url) async {}), throwsStateError);
    expect(await client.signedIn, isFalse);
    client.close();
  });
  test('Asset redirect never forwards GitHub credentials', () async {
    final payload = utf8.encode('package');
    var requests = 0;
    final client = Catalog(
      cacheDirectory: temp,
      client: MockClient((request) async {
        requests++;
        if (request.url.host == 'api.github.com') {
          expect(request.headers['Authorization'], 'Bearer test-token');
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

  test(
    'Revoked authorization during asset download requires sign-in again',
    () async {
      final client = Catalog(
        cacheDirectory: temp,
        client: MockClient((_) async => http.Response('', 401)),
      );
      final seed = (await client.cached()).first;
      await expectLater(
        client.download(
          ProjectManifest({...seed.json, 'asset_id': 1}),
          (_, _) {},
        ),
        throwsStateError,
      );
      expect(await client.signedIn, isFalse);
      expect((await client.cached()).single.hash, seed.hash);
      client.close();
    },
  );
}
