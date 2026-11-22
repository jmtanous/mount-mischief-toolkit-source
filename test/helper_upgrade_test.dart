import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/benro.dart';

class UpgradeDevice extends Benro {
  bool runtime = true, current = false, directoryExists = true;
  late Map<String, String> hashes = Map.of(Benro.compatibleHelperHashes);
  final calls = <String>[];
  UpgradeDevice()
    : super(
        host: '127.0.0.1',
        progress: (_) {},
        confirmKey: (_, _) async => false,
      );
  @override
  Future<int> otherControllers() async => 1;
  @override
  Future<bool> hasToolchain() async => runtime;
  @override
  Future<bool> hasHelpers() async => current;
  @override
  Future<String> shell(
    String command, {
    Stream<List<int>>? input,
    void Function(String)? onStderrLine,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (command.startsWith('sha256sum')) {
      return hashes.entries.map((e) => '${e.value}  $base/${e.key}').join('\n');
    }
    return directoryExists ? 'yes' : 'no';
  }

  @override
  Future<Map<String, dynamic>> call(
    String op, {
    String? project,
    Map<String, dynamic> fields = const {},
    Duration timeout = const Duration(minutes: 5),
  }) async {
    calls.add(op);
    return {
      'projects': [
        {'id': 'pilot', 'running': true},
      ],
      'operations': [],
    };
  }
}

void main() {
  test(
    'exact prior helper set exposes running projects and update notice',
    () async {
      final d = UpgradeDevice();
      final result = await d.inspect();
      expect(result['setup_update_required'], isTrue);
      expect((result['projects'] as List).single['running'], isTrue);
      expect(d.calls, ['list']);
    },
  );
  test('current helper set needs no update', () async {
    final d = UpgradeDevice()..current = true;
    expect((await d.inspect())['setup_update_required'], isFalse);
  });
  test(
    'missing, changed and mixed helper sets never execute the old manager',
    () async {
      for (final name in Benro.compatibleHelperHashes.keys) {
        for (final missing in [true, false]) {
          final d = UpgradeDevice();
          if (missing) {
            d.hashes.remove(name);
          } else {
            d.hashes[name] = 'unknown';
          }
          final result = await d.inspect();
          expect(result['setup_incomplete'], isTrue);
          expect(result['projects'], isEmpty);
          expect(d.calls, isEmpty);
        }
      }
    },
  );
  test('fresh card requires first setup, not repair', () async {
    final d = UpgradeDevice()
      ..runtime = false
      ..directoryExists = false;
    final result = await d.inspect();
    expect(result['setup_required'], isTrue);
    expect(result['setup_incomplete'], isFalse);
    expect(d.calls, isEmpty);
  });
  test('unusable runtime retains repair flow', () async {
    final d = UpgradeDevice()..runtime = false;
    expect((await d.inspect())['setup_incomplete'], isTrue);
    expect(d.calls, isEmpty);
  });
}
