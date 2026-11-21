import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/models.dart';

void main() {
  late Map<String, dynamic> seed;
  setUp(() {
    seed = Map<String, dynamic>.from(
      jsonDecode(File('assets/catalog.json').readAsStringSync())['projects'][0]
          as Map,
    );
  });
  test('Malformed or unsupported manifest values fail before use', () {
    final cases = <Map<String, dynamic>>[
      {'id': null},
      {'id': 123},
      {'id': '../outside'},
      {'version': null},
      {'version': ''},
      {'version': 42},
      {'name': []},
      {'sha256': 42},
      {'manifest_sha256': 'wrong'},
      {'archive_bytes': true},
      {'unpacked_bytes': 0},
      {'min_manager_schema': '1'},
      {'min_manager_schema': 2},
      {'adapter': 'unknown'},
      {
        'devices': ['other-device'],
      },
      {'devices': null},
      {'resources': []},
      {'resources': 'benro-controller'},
      {
        'resources': [...seed['resources'] as List, 123],
      },
      {
        'resources': [...seed['resources'] as List, 'tcp:8081'],
      },
      {'asset_id': '123'},
      {'asset_id': 0},
    ];
    for (final invalid in cases) {
      expect(
        () => ProjectManifest({...seed, ...invalid}),
        throwsFormatException,
        reason: invalid.toString(),
      );
    }
  });
  test(
    'Validated manifest cannot be changed through the source map or lists',
    () {
      final manifest = ProjectManifest(seed);
      final originalHash = manifest.hash;
      seed['sha256'] = '0' * 64;
      (seed['resources'] as List).clear();
      (seed['devices'] as List).clear();
      expect(manifest.hash, originalHash);
      expect(manifest.json['resources'], contains('benro-controller'));
      expect(manifest.json['devices'], ['benro-polaris']);
      expect(() => manifest.json['sha256'] = '0' * 64, throwsUnsupportedError);
      expect(
        () => (manifest.json['resources'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );
}
