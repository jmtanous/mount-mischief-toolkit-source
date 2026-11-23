// Full release packages, actual manager and standalone Python in the ARM lab.
// Controller heartbeat is intentionally stubbed: no physical mount is involved.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/benro.dart';
import 'package:mount_mischief_toolkit/models.dart';

import 'setup_vm_test.dart' as setup;

class NoControllerHeartbeat extends Keepalive {
  NoControllerHeartbeat() : super('127.0.0.1');
  @override
  Future<void> start() async {}
  @override
  void check() {}
  @override
  Future<void> close() async {}
}

class VersionDevice extends setup.LabDevice {
  VersionDevice(super.lab, super.root) {
    disconnectAfterActivation = false;
  }
  @override
  Keepalive createKeepalive() => NoControllerHeartbeat();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Real Beta 8 and 2.2.0 install, upgrade and rollback retain version settings', () async {
    final env = Platform.environment;
    final lab = env['MMT_LAB_DIR']!;
    final root = '/tmp/mmt-versions-${DateTime.now().microsecondsSinceEpoch}';
    final device = VersionDevice(lab, root);
    final catalog =
        jsonDecode(File('catalog-v2.json').readAsStringSync()) as Map;
    final manifests = (catalog['projects'] as List)
        .map((m) => ProjectManifest(Map<String, dynamic>.from(m)))
        .toList();
    final bootstrap = File(env['MMT_RUNTIME_ARCHIVE']!);
    final packages = [
      File(env['MMT_BETA8_ARCHIVE']!),
      File(env['MMT_PILOT220_ARCHIVE']!),
    ];
    Future<String> activeConfig() async {
      final record = jsonDecode(
        await device.shell(
          'cat ${quote('$root/projects/alpaca-pilot/installed.json')}',
        ),
      ) as Map;
      return '$root/projects/alpaca-pilot/releases/${record['release']}/opt/alpaca-pilot-2.2/data/config.pilot.json';
    }

    Future<void> save(String name) async {
      final cfg = await activeConfig();
      await device.shell(
        'printf %s ${quote(jsonEncode({'site_name': name, 'site_latitude': 12.5, 'site_longitude': -45.25}))} > ${quote(cfg)}',
      );
    }

    Future<void> expectSite(String name) async {
      final cfg = await activeConfig();
      final settings =
          jsonDecode(await device.shell('cat ${quote(cfg)}')) as Map;
      expect(settings['site_name'], name);
      expect(settings['site_latitude'], 12.5);
    }

    await device.hostCommand(
      'test ! -e ${quote('/opt/benro-bundle-target$root')} && sudo mkdir ${quote('/opt/benro-bundle-target$root')}',
    );
    try {
      await device.install(manifests[0], packages[0], bootstrap);
      await save('Beta settings');
      await device.install(
        manifests[1],
        packages[1],
        bootstrap,
        reinstall: true,
      );
      await expectSite('Beta settings');
      await save('Release settings');
      await device.install(
        manifests[0],
        packages[0],
        bootstrap,
        reinstall: true,
      );
      await expectSite('Beta settings');
      final snapshot =
          '$root/projects/alpaca-pilot/settings-by-release/${manifests[1].hash}.json';
      final saved =
          jsonDecode(await device.shell('cat ${quote(snapshot)}')) as Map;
      expect(saved['settings']['site_name'], 'Release settings');
      expect(
        device.archiveUploads,
        1,
        reason: 'Toolkit runtime is installed once for both project versions',
      );
    } finally {
      await device.hostCommand(
        'sudo rm -rf -- ${quote('/opt/benro-bundle-target$root')}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
