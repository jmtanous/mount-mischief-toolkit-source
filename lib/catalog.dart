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
  defaultValue: 'mount-mischief-toolkit-source',
);

class Catalog {
  final storage = const FlutterSecureStorage();
  final http.Client _client;
  final Directory? cacheDirectory;
  bool _credentialsRemoved = false;
  String? cacheNotice;
  ProjectManifest? _runtime;
  Catalog({http.Client? client, this.cacheDirectory})
    : _client = client ?? http.Client();

  // Retain secure storage for SSH pairing; delete only retired GitHub keys.
  Future<void> removeLegacyCredentials() async {
    if (_credentialsRemoved) return;
    try {
      await storage.delete(key: 'github_session');
      await storage.delete(key: 'github_token');
      _credentialsRemoved = true;
    } on PlatformException {
      cacheNotice = 'Old sign-in data could not be cleared. It is no longer used; cleanup will retry when the catalog reloads.';
    }
  }

  void close() => _client.close();

  String unavailable(String subject, int status, Map<String, String> headers) {
    if (status == 429 ||
        (status == 403 && headers['x-ratelimit-remaining'] == '0')) {
      return '$subject refresh/download limit reached. Try again later. Cached projects remain available.';
    }
    if (status == 404) {
      return '$subject is not available for public download yet. Cached projects remain available.';
    }
    return '$subject unavailable ($status). Try again later. Cached projects remain available.';
  }

  Future<T> internetRequest<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on SocketException {
      throw const HttpException(
        'Could not connect. Check internet access; cached projects remain available.',
      );
    } on http.ClientException {
      throw const HttpException(
        'Could not connect. Check internet access; cached projects remain available.',
      );
    } on TimeoutException {
      throw const HttpException(
        'Request timed out. Check internet access and retry; cached projects remain available.',
      );
    }
  }

  Future<Directory> get directory async {
    final root = cacheDirectory ?? await getApplicationSupportDirectory();
    return Directory('${root.path}/packages')..createSync(recursive: true);
  }

  Future<List<ProjectManifest>> cached() async {
    cacheNotice = null;
    await removeLegacyCredentials();
    final file = File('${(await directory).path}/catalog.json');
    if (await file.exists()) {
      try {
        return decodeCatalog(await file.readAsString());
      } on FormatException {
        cacheNotice = 'Saved catalog is invalid. Refresh the catalog when internet is available.';
      } on FileSystemException {
        cacheNotice = 'Saved catalog could not be read. Cached package files are preserved.';
      }
    }
    cacheNotice ??= 'Connect to the internet and refresh the catalog to choose a project.';
    return [];
  }

  List<ProjectManifest> decodeCatalog(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map ||
        ![1, 2].contains(decoded['schema']) ||
        decoded['projects'] is! List) {
      throw const FormatException('Unsupported catalog');
    }
    final runtime = decoded['runtime'];
    if (runtime != null) {
      final candidate = ProjectManifest(Map<String, dynamic>.from(runtime as Map));
      if (candidate.id != 'toolkit-runtime') throw const FormatException('Invalid Toolkit runtime');

    }
    final identities = <String>{};
    final projects = (decoded['projects'] as List).map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid catalog entry');
      }
      final manifest = ProjectManifest(entry, allowUnsupported: true);
      if (!identities.add('${manifest.id}\u0000${manifest.version}')) {
        throw const FormatException('Catalog repeats a project version');
      }
      return manifest;
    }).toList();
    _runtime = runtime == null ? null : ProjectManifest(Map<String, dynamic>.from(runtime as Map));
    return projects;
  }

  Future<List<ProjectManifest>> refresh() async {
    await removeLegacyCredentials();
    final uri = Uri.https(
      'api.github.com',
      '/repos/$catalogOwner/$catalogRepo/contents/catalog-v2.json',
    );
    final response = await internetRequest<http.Response>(
      () => _client
          .get(uri, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 25)),
    );
    if (response.statusCode != 200) {
      throw HttpException(
        unavailable('Catalog', response.statusCode, response.headers),
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
    throw StateError('${m.name} ${m.version} is not available offline. Download this version in Catalog before joining device Wi-Fi, or use Change version to install an available version.');
  }

  Future<ProjectManifest> runtimeManifest() async {
    final pinned = ProjectManifest(Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('assets/toolkit-runtime.json')) as Map));
    if (_runtime != null && (_runtime!.hash != pinned.hash || _runtime!.bytes != pinned.bytes)) {
      throw StateError('This catalog requires a newer Toolkit runtime. Update MMT first.');
    }
    return _runtime ?? pinned;
  }

  Future<File> bootstrap() async => bundled(await runtimeManifest());

  Future<bool> ready(ProjectManifest project) async =>
      await available(project) && await available(await runtimeManifest());

  Future<List<ProjectManifest>> pendingDownloads(ProjectManifest project) async {
    if (!project.supported) throw StateError('Update MMT required');
    final pending = <ProjectManifest>[];
    for (final package in [await runtimeManifest(), project]) {
      if (!await available(package)) pending.add(package);
    }
    return pending;
  }

  Future<int> requiredDownloadBytes(ProjectManifest project) async =>
      (await pendingDownloads(project)).fold<int>(0, (sum, p) => sum + p.bytes);

  Future<void> prepare(ProjectManifest project, void Function(int, int) progress) async {
    final packages = await pendingDownloads(project);
    final total = packages.fold<int>(0, (sum, p) => sum + p.bytes);
    var completed = 0;
    for (final package in packages) {
      await download(package, (count, _) => progress(completed + count, total));
      completed += package.bytes;
      progress(completed, total);
    }
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
      '/repos/${m.json['asset_owner'] ?? catalogOwner}/${m.json['asset_repo'] ?? catalogRepo}/releases/assets/${m.assetId}',
    );
    await removeLegacyCredentials();
    const requestHeaders = {'Accept': 'application/octet-stream'};
    http.StreamedResponse? response;
    for (var i = 0; i < 5; i++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(requestHeaders);
      response = await internetRequest<http.StreamedResponse>(
        () => _client.send(request).timeout(const Duration(seconds: 30)),
      );
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
        uri = next;
        response = null;
        continue;
      }
      await response.stream
          .listen((_) {})
          .cancel()
          .timeout(const Duration(seconds: 30));
      throw HttpException(
        unavailable('Package', response.statusCode, response.headers),
      );
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
