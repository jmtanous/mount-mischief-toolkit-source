import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

const catalogOwner = String.fromEnvironment(
  'CATALOG_OWNER',
  defaultValue: 'jmtanous',
);
const catalogRepo = String.fromEnvironment(
  'CATALOG_REPO',
  defaultValue: 'mount-mischief-catalog',
);
const oauthClientId = String.fromEnvironment(
  'GITHUB_CLIENT_ID',
  defaultValue: 'Ov23liMDXJ4LuW3hjHWP',
);

class Catalog {
  final storage = const FlutterSecureStorage();
  final http.Client _client;
  final Directory? cacheDirectory;
  final String clientId;
  final Future<void> Function(Duration) delay;
  bool cancelled = false;
  int _authGeneration = 0;
  Future<Map<String, dynamic>>? _refreshing;
  String? cacheNotice;
  Catalog({
    http.Client? client,
    this.cacheDirectory,
    this.clientId = oauthClientId,
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       delay = delay ?? Future<void>.delayed;
  Future<Directory> get directory async {
    final root = cacheDirectory ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/packages')..createSync(recursive: true);
  }

  Future<Map<String, dynamic>?> _session() async {
    final value = await storage.read(key: 'github_session');
    if (value != null) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic> ||
            decoded['access_token'] is! String ||
            (decoded['access_token'] as String).isEmpty ||
            (decoded['refresh_token'] != null &&
                decoded['refresh_token'] is! String) ||
            (decoded['expires_at'] != null && decoded['expires_at'] is! int)) {
          throw const FormatException('Invalid saved session');
        }
        return decoded;
      } on FormatException {
        await storage.delete(key: 'github_session');
        await storage.delete(key: 'github_token');
        return null;
      }
    }
    final legacy = await storage.read(key: 'github_token');
    return legacy == null ? null : {'access_token': legacy};
  }

  Future<bool> get signedIn async => await _session() != null;
  Future<void> signOut() async {
    cancelled = true;
    _authGeneration++;
    await storage.delete(key: 'github_session');
    await storage.delete(key: 'github_token');
  }

  void close() {
    cancelled = true;
    _authGeneration++;
    _client.close();
  }

  Future<Map<String, dynamic>> _saveSession(
    Map<String, dynamic> result,
    int generation,
  ) async {
    if (generation != _authGeneration) throw StateError('Sign-in cancelled');
    if (result['access_token'] is! String ||
        (result['access_token'] as String).isEmpty) {
      throw const FormatException('GitHub did not return an access token');
    }
    final session = <String, dynamic>{
      'access_token': result['access_token'],
      if (result['refresh_token'] is String)
        'refresh_token': result['refresh_token'],
      if (result['expires_in'] is num)
        'expires_at':
            DateTime.now().millisecondsSinceEpoch +
            (result['expires_in'] as num).toInt() * 1000,
    };
    // One secure-storage value keeps rotating token pairs together.
    await storage.write(key: 'github_session', value: jsonEncode(session));
    await storage.delete(key: 'github_token');
    return session;
  }

  Future<Map<String, dynamic>> _renew(Map<String, dynamic> session) async {
    final generation = _authGeneration;
    final refresh = session['refresh_token'];
    if (refresh is! String || refresh.isEmpty) {
      await signOut();
      throw StateError('GitHub authorization expired. Sign in again.');
    }
    final result = await post('/login/oauth/access_token', {
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    });
    if (generation != _authGeneration) throw StateError('Sign-in cancelled');
    if (result['error'] != null) {
      if (result['error'] == 'bad_refresh_token') await signOut();
      throw StateError('GitHub could not renew authorization. Sign in again.');
    }
    return _saveSession(result, generation);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, String> fields,
  ) async {
    final response = await _client
        .post(
          Uri.https('github.com', path),
          headers: {'Accept': 'application/json'},
          body: fields,
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw HttpException(
        'GitHub authorization failed (${response.statusCode})',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> signIn(
    Future<void> Function(String code, Uri url) showCode,
  ) async {
    if (clientId.isEmpty) {
      throw StateError(
        'This build needs a registered GitHub OAuth client ID. See setup documentation.',
      );
    }
    cancelled = false;
    final generation = ++_authGeneration;
    final device = await post('/login/device/code', {
      'client_id': clientId,
      'scope': 'repo',
    });
    if (device['error'] != null) {
      throw StateError(
        device['error_description']?.toString() ?? device['error'].toString(),
      );
    }
    final url = Uri.parse(device['verification_uri'] as String);
    if (url.scheme != 'https' || url.host != 'github.com') {
      throw StateError('Unexpected authorization address');
    }
    await showCode(device['user_code'] as String, url);
    var interval = (device['interval'] as num? ?? 5).toInt();
    final deadline = DateTime.now().add(
      Duration(seconds: (device['expires_in'] as num).toInt()),
    );
    while (!cancelled && DateTime.now().isBefore(deadline)) {
      await delay(Duration(seconds: interval));
      if (cancelled) break;
      final result = await post('/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': device['device_code'] as String,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      if (cancelled) break;
      if (result['access_token'] != null) {
        await _saveSession(result, generation);
        return;
      }
      switch (result['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        default:
          throw StateError(
            result['error_description']?.toString() ??
                'GitHub sign-in expired or was denied',
          );
      }
    }
    throw StateError(cancelled ? 'Sign-in cancelled' : 'Sign-in expired');
  }

  Future<Map<String, String>> headers() async {
    var session = await _session();
    if (session == null) {
      throw StateError('Sign in to GitHub to refresh the catalog');
    }
    final expires = session['expires_at'] as int?;
    if (expires != null &&
        DateTime.now().millisecondsSinceEpoch + 30000 >= expires) {
      final renewal = _refreshing ??= _renew(session);
      try {
        session = await renewal;
      } finally {
        if (identical(_refreshing, renewal)) _refreshing = null;
      }
    }
    return {
      'Authorization': 'Bearer ${session['access_token']}',
      'Accept': 'application/vnd.github+json',
    };
  }

  Future<List<ProjectManifest>> cached() async {
    cacheNotice = null;
    final file = File('${(await directory).path}/catalog.json');
    if (await file.exists()) {
      try {
        return decodeCatalog(await file.readAsString());
      } on FormatException {
        cacheNotice = 'Saved catalog is invalid. Showing the bundled project; refresh the catalog when internet is available.';
      } on FileSystemException {
        cacheNotice = 'Saved catalog could not be read. Showing the bundled project; cached package files are preserved.';
      }
    }
    return decodeCatalog(await rootBundle.loadString('assets/catalog.json'));
  }

  List<ProjectManifest> decodeCatalog(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map ||
        decoded['schema'] != 1 ||
        decoded['projects'] is! List) {
      throw const FormatException('Unsupported catalog');
    }
    final identities = <String>{};
    return (decoded['projects'] as List).map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid catalog entry');
      }
      final manifest = ProjectManifest(entry);
      if (!identities.add('${manifest.id}\u0000${manifest.version}')) {
        throw const FormatException('Catalog repeats a project version');
      }
      return manifest;
    }).toList();
  }

  Future<List<ProjectManifest>> refresh() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$catalogOwner/$catalogRepo/contents/catalog.json',
    );
    final response = await _client
        .get(uri, headers: await headers())
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 401) {
      await signOut();
      throw StateError('GitHub authorization expired. Sign in again.');
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'Catalog unavailable (${response.statusCode}). Check repository access. Cached packages remain available.',
      );
    }
    final envelope = jsonDecode(response.body) as Map;
    final content = utf8.decode(
      base64.decode((envelope['content'] as String).replaceAll('\n', '')),
    );
    final projects = decodeCatalog(content);
    final file = File('${(await directory).path}/catalog.json');
    await File('${file.path}.new').writeAsString(content, flush: true);
    await File('${file.path}.new').rename(file.path);
    cacheNotice = null;
    return projects;
  }

  Future<File> path(ProjectManifest m) async =>
      File('${(await directory).path}/${m.hash}.tar.gz');
  Future<bool> available(ProjectManifest m) async {
    final file = await path(m);
    return file.existsSync() &&
        file.lengthSync() == m.bytes &&
        (await sha256.bind(file.openRead()).first).toString() == m.hash;
  }

  Future<File> bundled(ProjectManifest m) async {
    if (await available(m)) return path(m);
    final text =
        jsonDecode(await rootBundle.loadString('assets/catalog.json')) as Map;
    final bundled = ProjectManifest(
      Map<String, dynamic>.from((text['projects'] as List).first as Map),
    );
    if (m.hash != bundled.hash) {
      throw StateError('Download this version before joining device Wi-Fi');
    }
    final bytes = await rootBundle.load('assets/runtime/pilot.tar.gz');
    final file = await path(m);
    await File('${file.path}.part').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    return finish(m, file);
  }

  Future<File> bootstrap() async {
    // Always select the shipped runtime, never a mutable catalog entry.
    final seed =
        jsonDecode(await rootBundle.loadString('assets/catalog.json')) as Map;
    return bundled(
      ProjectManifest(
        Map<String, dynamic>.from((seed['projects'] as List).first as Map),
      ),
    );
  }

  Future<File> finish(ProjectManifest m, File file) async {
    final part = File('${file.path}.part');
    if (await part.length() != m.bytes ||
        (await sha256.bind(part.openRead()).first).toString() != m.hash) {
      await part.delete();
      throw StateError('Downloaded package checksum failed');
    }
    return part.rename(file.path);
  }

  Future<File> download(
    ProjectManifest m,
    void Function(int, int) progress,
  ) async {
    if (await available(m)) return path(m);
    if (m.assetId == null) return bundled(m);
    final file = await path(m);
    var uri = Uri.https(
      'api.github.com',
      '/repos/$catalogOwner/$catalogRepo/releases/assets/${m.assetId}',
    );
    var auth = await headers();
    auth['Accept'] = 'application/octet-stream';
    http.StreamedResponse? response;
    for (var i = 0; i < 5; i++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(auth);
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) break;
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream
            .listen((_) {})
            .cancel()
            .timeout(const Duration(seconds: 30));
        if (location == null) throw StateError('Missing download redirect');
        final next = uri.resolve(location);
        if (next.scheme != 'https' || next.userInfo.isNotEmpty) {
          throw StateError('Unsafe download redirect');
        }
        if (next.origin != uri.origin) {
          auth = {}; // Never forward the GitHub token to asset storage.
        }
        uri = next;
        response = null;
        continue;
      }
      await response.stream
          .listen((_) {})
          .cancel()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 && auth.containsKey('Authorization')) {
        await signOut();
        throw StateError('GitHub authorization expired. Sign in again.');
      }
      throw HttpException('Package download failed (${response.statusCode})');
    }
    if (response == null || response.statusCode != 200) {
      throw StateError('Too many download redirects');
    }
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > m.bytes) {
          throw StateError('Download exceeds declared size');
        }
        sink.add(chunk);
        await sink.flush();
        progress(received, m.bytes);
      }
      await sink.close();
      return await finish(m, file);
    } catch (_) {
      // Failed transfers must not consume persistent offline storage or replace
      // the previous cached archive. Retry always starts a fresh .part file.
      try {
        await sink.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }
}
