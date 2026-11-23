import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/benro.dart';
import 'package:mount_mischief_toolkit/startup_progress.dart';

class LabHeartbeat extends Keepalive {
  LabHeartbeat(this.events) : super('127.0.0.1');
  final List<String> events;
  bool failStart = false;
  bool failCheck = false;
  bool active = false;
  Completer<void>? startGate;
  @override
  String? get peer => active ? '0100007F:ABCD' : null;
  @override
  Future<void> start() async {
    events.add('heartbeat:start');
    await startGate?.future;
    if (failStart) throw const SocketException('heartbeat unavailable');
    active = true;
  }

  @override
  void check() {
    events.add('heartbeat:check');
    if (failCheck) throw StateError('heartbeat lost');
  }

  @override
  Future<void> close() async {
    events.add('heartbeat:close');
    active = false;
  }
}

class StartLab extends Benro {
  StartLab(this.events, this.notices)
    : heartbeat = LabHeartbeat(events),
      super(
        host: '127.0.0.1',
        progress: notices.add,
        confirmKey: (_, _) async => false,
      );
  final List<String> events;
  final List<String> notices;
  final LabHeartbeat heartbeat;
  int clients = 0;
  List<String> peers = ['0100007F:ABCD'];
  @override
  Future<List<String>> controllerPeers() async => peers;
  @override
  Future<void> ensureToolchain(File bootstrap) async {
    events.add('repair');
    expect(heartbeat.active, isTrue);
  }

  final states = <Map<String, dynamic>>[
    {'running': false},
    {
      'running': true,
      'pilot': {'connected': false},
    },
    {
      'running': true,
      'pilot': {'connected': true, 'age517': 1},
    },
  ];
  final failures = <String, Object>{};
  final requests = <Map<String, dynamic>>[];

  @override
  Keepalive createKeepalive() => heartbeat;
  @override
  Future<int> controllers() async {
    events.add('controllers');
    return clients;
  }

  @override
  Future<Map<String, dynamic>> call(
    String op, {
    String? project,
    Map<String, dynamic> fields = const {},
    Duration timeout = const Duration(minutes: 5),
  }) async {
    events.add(op);
    requests.add({'op': op, 'project': project, ...fields});
    if (failures.containsKey(op)) throw failures[op]!;
    if (op == 'inspect') return states.removeAt(0);
    if (op == 'start') expect(heartbeat.active, isTrue);
    if (op == 'connect') expect(heartbeat.active, isFalse);
    return {};
  }
}

void main() {
  final site = Site('Confirmed field', 19.4, -99.1, 2200);
  late List<String> events, notices;
  late StartLab device;
  setUp(() {
    events = [];
    notices = [];
    device = StartLab(events, notices);
  });
  tearDown(() => device.close());

  test(
    'Paired heartbeat is reused across repair and released on disconnect',
    () async {
      await device.keepDeviceAwake();
      await device.keepDeviceAwake();
      await device.repairSetup(File('/unused-test-bootstrap'));
      expect(events.where((e) => e == 'heartbeat:start'), hasLength(1));
      expect(events, isNot(contains('heartbeat:close')));
      expect(device.holdingHeartbeat, isTrue);
      device.close();
      expect(device.holdingHeartbeat, isFalse);
      expect(device.heartbeat.active, isFalse);
    },
  );

  test(
    'Only the exact Toolkit endpoint is excluded from controllers',
    () async {
      await device.keepDeviceAwake();
      expect(await device.otherControllers(), 0);
      device.peers.add('0100007F:ABCE');
      expect(await device.otherControllers(), 1);
      await expectLater(device.repairSetup(File('/unused')), throwsStateError);
      expect(events, isNot(contains('repair')));
      device.peers.remove('0100007F:ABCD');
      await expectLater(device.otherControllers(), throwsStateError);
    },
  );

  test('Pairing leaves an existing controller in charge', () async {
    device.clients = 1;
    await device.keepDeviceAwake();
    expect(device.holdingHeartbeat, isFalse);
    expect(events, ['controllers']);
  });

  test(
    'A controller appearing during pairing releases Toolkit heartbeat',
    () async {
      device.peers.add('0100007F:ABCE');
      await expectLater(device.keepDeviceAwake(), throwsStateError);
      expect(device.holdingHeartbeat, isFalse);
      expect(device.heartbeat.active, isFalse);
    },
  );

  test('Closing while heartbeat starts cannot leave a live session', () async {
    final gate = device.heartbeat.startGate = Completer<void>();
    final pending = expectLater(device.keepDeviceAwake(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    device.close();
    gate.complete();
    await pending;
    expect(device.holdingHeartbeat, isFalse);
    expect(device.heartbeat.active, isFalse);
  });

  test('Pilot handover releases the existing paired heartbeat', () async {
    await device.keepDeviceAwake();
    final updates = <StartupEvent>[];
    final result = await device.start('alpaca-pilot', site, onProgress: updates.add);
    expect(updates.map((e) => e.stage).toSet().toList(), StartupStage.values);
    expect(updates.where((e) => e.responseReceived), hasLength(3));
    expect(result['pilot']['connected'], isTrue);
    expect(events.where((e) => e == 'heartbeat:start'), hasLength(1));
    expect(
      events.indexOf('heartbeat:close'),
      lessThan(events.indexOf('connect')),
    );
    expect(device.holdingHeartbeat, isFalse);
    expect(device.heartbeat.active, isFalse);
  });

  test(
    'Delayed readiness keeps reporting waiting status before handover',
    () async {
      device.states.insert(1, {'running': true});
      final updates = <StartupEvent>[];
      await device.start('alpaca-pilot', site, onProgress: updates.add);
      expect(
        updates.where(
          (e) => e.stage == StartupStage.waiting && e.responseReceived,
        ),
        hasLength(2),
      );
      expect(updates.last.stage, StartupStage.verifying);
      expect(updates.last.responseReceived, isTrue);
    },
  );

  test('Invalid site is rejected before all remote work', () async {
    await expectLater(
      device.start('alpaca-pilot', Site('Invalid', double.nan, 0, 0)),
      throwsArgumentError,
    );
    expect(events, isEmpty);
  });

  test(
    'Existing managed process is not restarted or given a second heartbeat',
    () async {
      device.states[0] = {'running': true};
      expect(await device.start('alpaca-pilot', site), {'running': true});
      expect(events, ['inspect']);
    },
  );

  for (final conflict in ['external Pilot', 'controller']) {
    test('$conflict prevents startup without device mutations', () async {
      if (conflict == 'external Pilot') {
        device.states[0] = {'running': false, 'external_pilot': {}};
      } else {
        device.clients = 1;
      }
      await expectLater(device.start('alpaca-pilot', site), throwsStateError);
      expect(events, isNot(contains('heartbeat:start')));
      expect(events, isNot(contains('start')));
      expect(events, isNot(contains('stop')));
    });
  }

  test(
    'Start holds heartbeat until API readiness then connects Pilot',
    () async {
      final before = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final result = await device.start('alpaca-pilot', site);
      expect(result['pilot']['connected'], isTrue);
      expect(events, [
        'inspect',
        'controllers',
        'heartbeat:start',
        'start',
        'heartbeat:check',
        'inspect',
        'heartbeat:close',
        'controllers',
        'connect',
        'inspect',
        'heartbeat:close',
      ]);
      final request = device.requests.singleWhere((r) => r['op'] == 'start');
      expect(request['project'], 'alpaca-pilot');
      expect(request['site'], site.toJson());
      expect(request['epoch'], greaterThanOrEqualTo(before));
      expect(request['operation'], matches(RegExp(r'^op-[a-f0-9]{32}$')));
      expect(device.heartbeat.active, isFalse);
    },
  );

  test(
    'Heartbeat failure before launch never starts or stops a project',
    () async {
      device.heartbeat.failStart = true;
      await expectLater(
        device.start('alpaca-pilot', site),
        throwsA(isA<SocketException>()),
      );
      expect(events, isNot(contains('start')));
      expect(events, isNot(contains('stop')));
      expect(events.last, 'heartbeat:close');
    },
  );

  test(
    'Heartbeat loss after launch stops the owned project before exit',
    () async {
      device.heartbeat.failCheck = true;
      await expectLater(device.start('alpaca-pilot', site), throwsStateError);
      expect(
        events,
        containsAllInOrder([
          'start',
          'heartbeat:check',
          'stop',
          'heartbeat:close',
        ]),
      );
      expect(events, isNot(contains('connect')));
    },
  );

  test('Pilot exiting before readiness never receives connect', () async {
    device.states[1] = {'running': false};
    final updates = <StartupEvent>[];
    await expectLater(
      device.start('alpaca-pilot', site, onProgress: updates.add),
      throwsStateError,
    );
    expect(updates.last.cleanup, StartupCleanup.confirmed);
    expect(updates.last.stage, StartupStage.waiting);
    expect(
      events,
      containsAllInOrder(['start', 'inspect', 'stop', 'heartbeat:close']),
    );
    expect(events, isNot(contains('connect')));
  });

  test('Failed handover cleans up and preserves the original error if cleanup is uncertain', () async {
    final failure = const SocketException('lost during handover');
    device.failures['connect'] = failure;
    device.failures['stop'] = TimeoutException('cleanup reply lost');
    final updates = <StartupEvent>[];
    await expectLater(
      device.start('alpaca-pilot', site, onProgress: updates.add),
      throwsA(same(failure)),
    );
    expect(updates.where((e) => e.cleanup != null).map((e) => e.cleanup), [
      StartupCleanup.stopping,
      StartupCleanup.uncertain,
    ]);
    expect(updates.last.stage, StartupStage.handover);
    expect(
      events,
      containsAllInOrder([
        'heartbeat:close',
        'connect',
        'stop',
        'heartbeat:close',
      ]),
    );
    expect(
      notices.last,
      'Cleanup could not be confirmed. Reconnect and inspect the device.',
    );
    expect(device.heartbeat.active, isFalse);
  });
}
