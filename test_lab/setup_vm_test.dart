// Explicit local lab integration. Never points at a physical device.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/benro.dart';

class LabDevice extends Benro {
  final String lab;
  int archiveUploads = 0;
  bool disconnectAfterActivation = true;
  LabDevice(this.lab, String root)
    : super(
        host: '127.0.0.1',
        base: root,
        progress: (_) {},
        confirmKey: (_, _) async => false,
      );

  Future<String> hostCommand(
    String command, {
    Stream<List<int>>? input,
    void Function(String)? onStderrLine,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final process = await Process.start('ssh', [
      '-F',
      '/dev/null',
      '-p',
      '2223',
      '-i',
      '$lab/state/id_ed25519',
      '-o',
      'BatchMode=yes',
      '-o',
      'IdentitiesOnly=yes',
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'UserKnownHostsFile=$lab/state/known_hosts',
      '-o',
      'ConnectTimeout=8',
      'dev@127.0.0.1',
      command,
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          onStderrLine?.call(line);
          return line;
        })
        .join('\n');
    try {
      final completion = () async {
        if (input != null) await process.stdin.addStream(input);
        await process.stdin.close();
        final result = await process.exitCode;
        final stdout = await output;
        final stderr = await errors;
        if (result != 0) {
          throw StateError('Lab command failed ($result): $stderr $stdout');
        }
        return stdout.trim();
      }();
      return await completion.timeout(timeout);
    } finally {
      process.kill();
    }
  }

  @override
  Future<String> shell(
    String command, {
    Stream<List<int>>? input,
    void Function(String)? onStderrLine,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = await hostCommand(
      'sudo chroot /opt/benro-bundle-target /bin/sh -c ${quote(command)}',
      input: input,
      onStderrLine: onStderrLine,
      timeout: timeout,
    );
    if (disconnectAfterActivation && command.contains('tar -xzf')) {
      disconnectAfterActivation = false;
      throw TimeoutException('Simulated lost reply after runtime activation');
    }
    return result;
  }

  @override
  Future<int> controllers() async => 0; // This chroot has no controller or /proc mount.

  @override
  Future<void> upload(File file, String destination) async {
    if (destination.endsWith('/archive.tar.gz')) archiveUploads++;
    await super.upload(file, destination);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Actual ARM setup recovers lost activation reply, missing helpers and damaged Python', () async {
    final lab = Platform.environment['MMT_LAB_DIR'];
    if (lab == null) {
      throw StateError(
        'Run scripts/test-setup-vm.sh to select the isolated lab.',
      );
    }
    final root = '/tmp/mmt-bootstrap-${DateTime.now().microsecondsSinceEpoch}';
    final device = LabDevice(lab, root);
    final archivePath = Platform.environment['MMT_RUNTIME_ARCHIVE'];
    if (archivePath == null) {
      throw StateError(
        'Set MMT_RUNTIME_ARCHIVE to the verified standalone Toolkit archive',
      );
    }
    final archive = File(archivePath);
    if (!archive.existsSync()) {
      throw StateError('Toolkit runtime archive is missing');
    }
    await device.hostCommand(
      'test ! -e ${quote('/opt/benro-bundle-target$root')} && sudo mkdir ${quote('/opt/benro-bundle-target$root')}',
    );
    try {
      await expectLater(
        device.ensureToolchain(archive),
        throwsA(isA<TimeoutException>()),
      );
      expect(await device.hasToolchain(), isTrue);
      expect(await device.hasHelpers(), isFalse);
      expect((await device.inspect())['setup_incomplete'], isTrue);
      await device.ensureToolchain(archive);
      expect(await device.hasHelpers(), isTrue);
      expect(
        device.archiveUploads,
        1,
        reason:
            'A lost activation reply must not require another runtime upload',
      );
      expect((await device.inspect())['projects'], isEmpty);

      await device.shell(
        'mkdir -p ${quote('$root/projects/preserved')} && printf saved > ${quote('$root/projects/preserved/settings.json')} && rm ${quote('$root/pilot_adapter.py')}',
      );
      expect((await device.inspect())['setup_incomplete'], isTrue);
      await device.ensureToolchain(archive);
      expect(await device.hasHelpers(), isTrue);
      expect(device.archiveUploads, 1);

      await device.shell(
        'printf broken > ${quote('${device.python}/bin/python3.13')}',
      );
      expect(await device.hasToolchain(), isFalse);
      expect((await device.inspect())['setup_incomplete'], isTrue);
      await device.ensureToolchain(archive);
      expect(await device.hasToolchain(), isTrue);
      expect(await device.hasHelpers(), isTrue);
      expect(device.archiveUploads, 2);
      expect(
        await device.shell(
          'cat ${quote('$root/projects/preserved/settings.json')}',
        ),
        'saved',
      );
      expect(
        await device.shell(
          'for directory in ${quote(root)}/toolchain-backup-*; do test -d "\$directory" && cat "\$directory/opt/benro-python/bin/python3.13"; done',
        ),
        'broken',
      );
      expect((await device.inspect())['projects'], isEmpty);
    } finally {
      // Only the directory created by this test is removed.
      await device.hostCommand(
        'sudo rm -rf -- ${quote('/opt/benro-bundle-target$root')}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
