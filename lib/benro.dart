import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';
import 'startup_progress.dart';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

const deviceHost = '192.168.0.1';
const bundleHash =
    'a0e8911e1f40694dbcd79055f9b8d84f714dad503f1eaf4039c2a9f8f13ca734';
const toolkitBase = '/app/sd/mount-mischief-toolkit';
String quote(String s) => "'${s.replaceAll("'", "'\\''")}'";

class Site {
  final String name;
  final double latitude, longitude, elevation;
  Site(this.name, this.latitude, this.longitude, this.elevation);
  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
  };
  void validate() {
    if (name.trim().isEmpty ||
        name.length > 120 ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !elevation.isFinite ||
        elevation < -500 ||
        elevation > 10000) {
      throw ArgumentError(
        'Enter a valid site, latitude, longitude and elevation.',
      );
    }
  }
}

class Keepalive {
  final String host;
  final int port;
  final InternetAddress? sourceAddress;
  Keepalive(this.host, {this.port = 9090, this.sourceAddress});
  Socket? _socket;
  Timer? _timer;
  String _buffer = '';
  DateTime _last = DateTime.now();
  final _context = Completer<void>();
  String? error;
  bool _closed = false;
  String? get peer {
    final socket = _socket;
    if (socket == null || _closed || error != null) return null;
    // Socket.address is the destination used by Socket.connect, not the
    // actual local interface. Bind explicitly to the SSH client's address.
    final address = sourceAddress?.rawAddress;
    if (address == null || address.length != 4) return null;
    return '${address.reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}:${socket.port.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }

  Future<void> start() async {
    _socket = await Socket.connect(
      host,
      port,
      sourceAddress: sourceAddress,
      timeout: const Duration(seconds: 8),
    );
    if (_closed) {
      _socket!.destroy();
      _socket = null;
      throw StateError('Keepalive was closed');
    }
    _socket!.listen(
      (data) {
        _buffer += ascii.decode(data, allowInvalid: true);
        while (_buffer.contains('#')) {
          final end = _buffer.indexOf('#');
          final frame = _buffer.substring(0, end);
          _buffer = _buffer.substring(end + 1);
          if (frame.startsWith('808@ret:0')) {
            if (!_context.isCompleted) _context.complete();
            _last = DateTime.now();
          } else if (frame == 'h' || frame.startsWith('284@')) {
            _last = DateTime.now();
          }
        }
        if (_buffer.length > 8192) {
          _buffer = '';
          _fail('Invalid keepalive response');
        }
      },
      onError: (Object e) => _fail(e.toString()),
      onDone: () {
        if (!_closed) _fail('Keepalive connection closed');
      },
    );
    _socket!.write('1&808&2&type:0;#');
    await _socket!.flush();
    await _context.future.timeout(const Duration(seconds: 12));
    check();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_last).inSeconds > 25) {
        _fail('Device stopped replying');
        return;
      }
      try {
        _socket?.write('h#1&284&2&-1#');
      } catch (e) {
        _fail(e.toString());
      }
    });
  }

  void _fail(String reason) {
    error ??= reason;
    if (!_context.isCompleted) _context.complete();
    _timer?.cancel();
    _socket?.destroy();
    _socket = null;
  }

  void check() {
    if (error != null) throw StateError(error!);
    if (_closed || _socket == null) throw StateError('Keepalive is closed');
  }

  Future<void> close() async {
    _closed = true;
    if (!_context.isCompleted) _context.complete();
    _timer?.cancel();
    _socket?.destroy();
    _socket = null;
  }
}

class Benro {
  final String host;
  final String base;
  final void Function(String) progress;
  final Future<bool> Function(String, String) confirmKey;
  final storage = const FlutterSecureStorage();
  SSHClient? _client;
  InternetAddress? _heartbeatSourceAddress;
  Keepalive? _sessionHeartbeat;
  bool get holdingHeartbeat => _sessionHeartbeat != null;
  bool _closed = false;
  int _connectionGeneration = 0;
  String get python => '$base/toolchain/opt/benro-python';
  Benro({
    required this.host,
    required this.progress,
    required this.confirmKey,
    this.base = toolkitBase,
    SSHClient? client,
  }) {
    _client = client;
  }
  String operationId() =>
      'op-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  Keepalive createKeepalive() =>
      Keepalive(host, sourceAddress: _heartbeatSourceAddress);

  static InternetAddress heartbeatSourceAddress(String connection) {
    final parts = connection.trim().split(RegExp(r'\s+'));
    final address = InternetAddress.tryParse(parts.first);
    if (parts.length != 4 ||
        address?.type != InternetAddressType.IPv4 ||
        int.tryParse(parts[1]) == null ||
        InternetAddress.tryParse(parts[2])?.type != InternetAddressType.IPv4 ||
        parts[3] != '22') {
      throw StateError('Device did not report a valid SSH client address');
    }
    return address!;
  }

  Future<void> keepDeviceAwake() async {
    final generation = _connectionGeneration;
    if (_sessionHeartbeat != null) {
      _sessionHeartbeat!.check();
      return;
    }
    // An existing controller owns its own heartbeat. Do not take it over.
    if (await controllers() != 0) return;
    final heartbeat = createKeepalive();
    try {
      await heartbeat.start();
      if (_closed || generation != _connectionGeneration) {
        throw StateError('Device session closed during heartbeat setup');
      }
      _sessionHeartbeat = heartbeat;
      if (await otherControllers() != 0) {
        throw StateError('Another controller connected during pairing');
      }
    } catch (_) {
      _sessionHeartbeat = null;
      await heartbeat.close();
      rethrow;
    }
  }

  Future<void> releaseHeartbeat() async {
    final heartbeat = _sessionHeartbeat;
    _sessionHeartbeat = null;
    await heartbeat?.close();
  }

  Future<int> otherControllers() async {
    final heartbeat = _sessionHeartbeat;
    if (heartbeat == null) return controllers();
    heartbeat.check();
    final ownPeer = heartbeat.peer;
    if (ownPeer == null) {
      throw StateError('Toolkit heartbeat identity is unavailable');
    }
    final peers = await controllerPeers();
    if (!peers.contains(ownPeer)) {
      throw StateError(
        'Toolkit heartbeat disconnected. Pair and inspect again.',
      );
    }
    // Exclude only our exact TCP endpoint, never subtract an assumed client.
    return peers.where((peer) => peer != ownPeer).length;
  }

  Future<List<String>> controllerPeers() async {
    final raw = await shell(
      "awk 'NR>1 && \$2 ~ /:2382\$/ && \$4==\"01\" {print \$3}' /proc/net/tcp",
      timeout: const Duration(seconds: 15),
    );
    return raw
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .toList();
  }

  String describeError(Object error) {
    if (error is SSHSocketError ||
        error is SocketException ||
        error is TimeoutException) {
      return 'Connection to $host was lost or timed out. Rejoin the device Wi-Fi and use Pair and inspect before retrying. Polaris can disable Wi-Fi after about 60 seconds without a heartbeat.\nDetails: $error';
    }
    return error.toString();
  }

  Future<String> shell(
    String command, {
    Stream<List<int>>? input,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final client = _client;
    if (client == null || _closed) {
      throw StateError('Connect to the device first');
    }
    SSHSession? active;
    StreamIterator<List<int>>? uploadChunks;
    var expired = false;
    Future<String> run() async {
      final session = await client.execute(command);
      active = session;
      if (expired) {
        session.close();
        throw TimeoutException('SSH command expired');
      }
      Future<List<int>> collect(Stream<Uint8List> stream) async {
        final bytes = <int>[];
        await for (final chunk in stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            session.close();
            throw StateError('Device response too large');
          }
          bytes.addAll(chunk);
        }
        return bytes;
      }

      final output = Future.wait([
        collect(session.stdout),
        collect(session.stderr),
      ], eagerError: true);
      final write = () async {
        if (input != null) {
          // A transport flush locks Dart's socket sink while the SSH channel
          // can still emit packets. Stream through stdin without racing that
          // independent writer; EOF and remote exit confirm completion.
          final chunks = uploadChunks = StreamIterator(input);
          while (await chunks.moveNext()) {
            if (expired) throw TimeoutException('Upload expired');
            session.write(Uint8List.fromList(chunks.current));
          }
        }
        await session.stdin.close();
        await session.done;
      }();
      final completed = await Future.wait<Object?>([
        output,
        write,
      ], eagerError: true);
      final streams = completed.first as List<List<int>>;
      final stdout = utf8.decode(streams[0], allowMalformed: true);
      final stderr = utf8.decode(streams[1], allowMalformed: true);
      if (session.exitCode != 0) {
        final signal = session.exitSignal;
        final detail = '$stdout\n$stderr'.trim();
        throw StateError(
          'Device command ${command.split(' ').first} failed '
          '(exit ${session.exitCode ?? 'not reported'}'
          '${signal == null ? '' : ', signal ${signal.signalName}'}). '
          '${detail.isEmpty ? 'No error output was returned.' : detail}',
        );
      }
      return stdout.trim();
    }

    try {
      return await run().timeout(timeout);
    } finally {
      expired = true;
      await uploadChunks?.cancel();
      active?.close();
    }
  }

  Future<void> open() async {
    close();
    _closed = false;
    if (InternetAddress.tryParse(host)?.type != InternetAddressType.IPv4) {
      throw ArgumentError('Enter the device IPv4 address');
    }
    String? accepted;
    final saved = await storage.read(key: 'device-key:$host');
    progress('Verifying device identity…');
    final client = SSHClient(
      await SSHSocket.connect(host, 22, timeout: const Duration(seconds: 10)),
      username: 'root',
      onVerifyHostKey: (type, bytes) async {
        final fingerprint = utf8.decode(bytes, allowMalformed: true);
        if (!fingerprint.startsWith('SHA256:')) return false;
        if (saved != null) {
          if (saved != fingerprint) {
            throw StateError(
              'Device identity changed. Pairing has been blocked.',
            );
          }
          return true;
        }
        if (await confirmKey(host, fingerprint)) {
          accepted = fingerprint;
          return true;
        }
        return false;
      },
      keepAliveInterval: const Duration(seconds: 10),
      handshakeTimeout: const Duration(seconds: 20),
      authTimeout: const Duration(seconds: 20),
    );
    _client = client;
    try {
      await client.authenticated.timeout(const Duration(seconds: 60));
      if (accepted != null) {
        await storage.write(key: 'device-key:$host', value: accepted);
      }
      await shell(
        "awk '\$2==\"/app/sd\" && \$3==\"vfat\" {ok=1} END {exit !ok}' /proc/mounts",
        timeout: const Duration(seconds: 15),
      );
      final arch = await shell(
        'uname -m',
        timeout: const Duration(seconds: 15),
      );
      if (!['armv7l', 'armv8l'].contains(arch)) {
        throw StateError('Unsupported device architecture: $arch');
      }
      _heartbeatSourceAddress = heartbeatSourceAddress(
        await shell(
          'printf \'%s\' "\$SSH_CONNECTION"',
          timeout: const Duration(seconds: 15),
        ),
      );
      await keepDeviceAwake();
      progress('Paired. Device SD card is available.');
    } catch (_) {
      close();
      rethrow;
    }
  }

  Future<bool> hasToolchain() async =>
      await shell(
        'if env PYTHONNOUSERSITE=1 LD_LIBRARY_PATH=${quote('$python/lib:/lib:/usr/lib:/app/lib')} ${quote('$python/bin/python3.13')} -I -c ${quote('import hashlib, json, tarfile, fcntl')} >/dev/null 2>&1; then echo yes; else echo no; fi',
        timeout: const Duration(seconds: 15),
      ) ==
      'yes';

  Future<bool> hasHelpers() async {
    const names = ['manager.py', 'pilot_adapter.py', 'pilot_native.py'];
    final output = await shell(
      'sha256sum ${names.map((name) => quote('$base/$name')).join(' ')} 2>/dev/null || true',
      timeout: const Duration(seconds: 15),
    );
    final checksums = <String, String>{};
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2) checksums[parts[1]] = parts[0];
    }
    for (final name in names) {
      final bytes = await rootBundle.load('assets/helper/$name');
      final expected = sha256
          .convert(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          )
          .toString();
      if (checksums['$base/$name'] != expected) return false;
    }
    return true;
  }

  Future<int> controllers() async => int.parse(
    await shell(
      "awk 'NR>1 && \$2 ~ /:2382\$/ && \$4==\"01\" {n++} END {print n+0}' /proc/net/tcp",
      timeout: const Duration(seconds: 15),
    ),
  );
  Future<void> upload(File file, String destination) async {
    final size = await file.length();
    var sent = 0;
    var last = -1;
    final stream = file.openRead().map((chunk) {
      sent += chunk.length;
      final percent = (sent * 100 / size).floor();
      if (percent != last) {
        last = percent;
        progress('Uploading package: $percent%');
      }
      return chunk;
    });
    await shell(
      'cat > ${quote(destination)}',
      input: stream,
      timeout: const Duration(minutes: 15),
    );
  }

  Future<void> ensureToolchain(File bundled) async {
    progress('Checking the SD runtime…');
    if (!await hasToolchain()) {
      progress('Verifying the local runtime archive…');
      if ((await sha256.bind(bundled.openRead()).first).toString() !=
          bundleHash) {
        throw StateError('Bootstrap archive failed verification');
      }
      progress('Checking free SD space…');
      final space = (await shell(
        "stat -f -c '%a %S' ${quote(Directory(base).parent.path)}",
      )).split(RegExp(r'\s+'));
      if (space.length != 2 ||
          space.any((part) => int.tryParse(part) == null)) {
        throw StateError('Could not determine available SD space');
      }
      final free = int.parse(space[0]) * int.parse(space[1]);
      if (free < 700 * 1024 * 1024) {
        throw StateError(
          'At least 700 MiB of free SD space is needed for initial setup',
        );
      }
      final stage = '$base/bootstrap-${operationId()}';
      final backup = '$base/toolchain-backup-${operationId()}';
      progress('Creating the SD staging directory…');
      await shell('mkdir -p ${quote(stage)}');
      await upload(bundled, '$stage/archive.tar.gz');
      progress('Verifying the uploaded runtime archive…');
      final actual = await shell('sha256sum ${quote('$stage/archive.tar.gz')}');
      if (actual.split(' ').first != bundleHash) {
        throw StateError('Bootstrap transfer checksum failed');
      }
      // This exact pinned bundle was audited to contain only regular files/directories.
      progress('Preparing the SD runtime…');
      await shell(
        'tar -xzf ${quote('$stage/archive.tar.gz')} -C ${quote(stage)} && '
        'env PYTHONNOUSERSITE=1 LD_LIBRARY_PATH=${quote('$stage/opt/benro-python/lib:/lib:/usr/lib:/app/lib')} ${quote('$stage/opt/benro-python/bin/python3.13')} -I -c ${quote('import hashlib, json, tarfile, fcntl')} && '
        'rm ${quote('$stage/archive.tar.gz')} && '
        '(if test -e ${quote('$base/toolchain')}; then mv ${quote('$base/toolchain')} ${quote(backup)}; fi) && '
        'mv ${quote(stage)} ${quote('$base/toolchain')}',
        timeout: const Duration(minutes: 15),
      );
    }
    progress('Preparing Toolkit helper files…');
    await shell('mkdir -p ${quote('$base/inbox')}');
    for (final name in ['manager.py', 'pilot_adapter.py', 'pilot_native.py']) {
      final bytes = await rootBundle.load('assets/helper/$name');
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final destination = '$base/$name';
      progress('Updating Toolkit helper: $name…');
      await shell(
        'cat > ${quote('$destination.new')}',
        input: Stream.value(data),
      );
      final checksum = await shell('sha256sum ${quote('$destination.new')}');
      if (checksum.split(' ').first != sha256.convert(data).toString()) {
        throw StateError('Helper transfer checksum failed');
      }
      await shell('mv ${quote('$destination.new')} ${quote(destination)}');
    }
  }

  Future<Map<String, dynamic>> call(
    String op, {
    String? project,
    Map<String, dynamic> fields = const {},
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final request = {'op': op, 'project': ?project, ...fields};
    final command =
        'env PYTHONNOUSERSITE=1 LD_LIBRARY_PATH=${quote('$python/lib:/lib:/usr/lib:/app/lib')} ${quote('$python/bin/python3.13')} -B ${quote('$base/manager.py')}';
    final raw = await shell(
      command,
      input: Stream.value(utf8.encode(jsonEncode(request))),
      timeout: timeout,
    );
    final response = jsonDecode(raw) as Map<String, dynamic>;
    if (response['ok'] != true) throw StateError(response['error'].toString());
    return Map<String, dynamic>.from(response['result'] as Map);
  }

  Future<Map<String, dynamic>> inspect() async {
    final count = await otherControllers();
    if (!await hasToolchain() || !await hasHelpers()) {
      final exists = await shell(
        'if test -d ${quote(base)}; then echo yes; else echo no; fi',
      );
      return {
        'projects': [],
        'operations': [],
        'controller_clients': count,
        'setup_incomplete': exists == 'yes',
      };
    }
    return {
      ...await call('list', timeout: const Duration(seconds: 40)),
      'controller_clients': count,
    };
  }

  Future<void> repairSetup(File bootstrap) async {
    if (await otherControllers() != 0) {
      throw StateError(
        'Disconnect active controllers before repairing Toolkit setup.',
      );
    }
    final borrowed = _sessionHeartbeat != null;
    final heartbeat = _sessionHeartbeat ?? createKeepalive();
    try {
      if (!borrowed) await heartbeat.start();
      await ensureToolchain(bootstrap);
      heartbeat.check();
      progress('Toolkit setup repaired. Project files have been preserved.');
    } finally {
      if (!borrowed) await heartbeat.close();
    }
  }

  Future<void> install(
    ProjectManifest manifest,
    File archive,
    File bootstrap, {
    bool reinstall = false,
    bool keepSettings = true,
  }) async {
    if (await otherControllers() != 0) {
      throw StateError(
        'Another controller is connected. Disconnect it before installation.',
      );
    }
    final borrowed = _sessionHeartbeat != null;
    final heartbeat = _sessionHeartbeat ?? createKeepalive();
    try {
      if (!borrowed) await heartbeat.start();
      await ensureToolchain(bootstrap);
      heartbeat.check();
      final operation = operationId();
      await call(
        'stage',
        project: manifest.id,
        fields: {
          'operation': operation,
          'action': reinstall ? 'reinstall' : 'install',
          'manifest': manifest.json,
          'keep_settings': keepSettings,
        },
      );
      await upload(archive, '$base/inbox/$operation.tar.gz.part');
      await shell(
        'mv ${quote('$base/inbox/$operation.tar.gz.part')} ${quote('$base/inbox/$operation.tar.gz')}',
      );
      heartbeat.check();
      progress('Verifying and installing ${manifest.name}…');
      await call(
        reinstall ? 'reinstall' : 'install',
        project: manifest.id,
        fields: {
          'operation': operation,
          'manifest': manifest.json,
          'keep_settings': keepSettings,
        },
        timeout: const Duration(minutes: 15),
      );
      progress('${manifest.name} installed. Start it when ready.');
    } finally {
      if (!borrowed) await heartbeat.close();
    }
  }

  Future<void> stop(String project) async {
    await call('stop', project: project, fields: {'operation': operationId()});
    await keepDeviceAwake();
  }

  Future<void> uninstall(String project, bool keepSettings) async {
    await call(
      'uninstall',
      project: project,
      fields: {'operation': operationId(), 'keep_settings': keepSettings},
    );
  }

  Future<Map<String, dynamic>> start(
    String project,
    Site site, {
    void Function(StartupEvent)? onProgress,
  }) async {
    var stage = StartupStage.checking;
    void report(
      StartupStage value, {
      bool response = false,
      bool existing = false,
      StartupCleanup? cleanup,
    }) {
      stage = value;
      onProgress?.call(
        StartupEvent(
          value,
          responseReceived: response,
          alreadyRunning: existing,
          cleanup: cleanup,
        ),
      );
    }

    report(stage);
    site.validate();
    final current = await call('inspect', project: project);
    report(stage, response: true);
    if (current['running'] == true) {
      report(StartupStage.verifying, existing: true);
      return current;
    }
    if (current['external_pilot'] != null || await otherControllers() != 0) {
      throw StateError('Another controller or unmanaged Pilot is running');
    }
    final borrowed = _sessionHeartbeat != null;
    final heartbeat = _sessionHeartbeat ?? createKeepalive();
    var started = false;
    try {
      if (!borrowed) await heartbeat.start();
      report(StartupStage.launching);
      progress('Starting Pilot with the confirmed time and location…');
      await call(
        'start',
        project: project,
        fields: {
          'operation': operationId(),
          'site': site.toJson(),
          'epoch': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        },
      );
      started = true;
      report(StartupStage.waiting);
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (true) {
        heartbeat.check();
        final status = await call(
          'inspect',
          project: project,
          timeout: const Duration(seconds: 25),
        );
        report(stage, response: true);
        if (status['pilot'] != null) break;
        if (status['running'] != true) {
          throw StateError('Pilot exited. Read diagnostics before retrying.');
        }
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Pilot startup timed out');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      report(StartupStage.handover);
      progress('Handing the controller connection to Pilot…');
      if (borrowed) _sessionHeartbeat = null;
      await heartbeat.close();
      for (var i = 0; i < 10 && await controllers() != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await call(
        'connect',
        project: project,
        fields: {'operation': operationId()},
      );
      report(StartupStage.verifying);
      final connectedDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(connectedDeadline)) {
        final state = await call(
          'inspect',
          project: project,
          timeout: const Duration(seconds: 25),
        );
        report(stage, response: true);
        final pilot = state['pilot'] as Map?;
        if (pilot?['connected'] == true &&
            (pilot?['age517'] as num? ?? 999) < 5) {
          progress(
            'Pilot connected. It will keep running when you close Toolkit.',
          );
          return state;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw TimeoutException('Pilot connection did not become ready');
    } catch (_) {
      if (started) {
        report(stage, cleanup: StartupCleanup.stopping);
        try {
          // Failure cleanup must not acquire a replacement heartbeat.
          await call(
            'stop',
            project: project,
            fields: {'operation': operationId()},
          );
          report(stage, cleanup: StartupCleanup.confirmed);
        } catch (_) {
          report(stage, cleanup: StartupCleanup.uncertain);
          progress(
            'Cleanup could not be confirmed. Reconnect and inspect the device.',
          );
        }
      }
      rethrow;
    } finally {
      if (identical(_sessionHeartbeat, heartbeat)) _sessionHeartbeat = null;
      await heartbeat.close();
    }
  }

  void close() {
    _connectionGeneration++;
    unawaited(releaseHeartbeat());
    _closed = true;
    _client?.close();
    _client = null;
    _heartbeatSourceAddress = null;
  }
}
