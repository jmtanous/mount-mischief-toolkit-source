part of '../benro.dart';

// Pilot-specific startup and controller handover. Not a generic project protocol.
Future<Map<String, dynamic>> startPilot(
  Benro device,
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
    final current = await device.call('inspect', project: project);
    report(stage, response: true);
    if (current['running'] == true) {
      report(StartupStage.verifying, existing: true);
      return current;
    }
    if (current['external_pilot'] != null || await device.otherControllers() != 0) {
      throw StateError('Another controller or unmanaged Pilot is running');
    }
    final borrowed = device._sessionHeartbeat != null;
    final heartbeat = device._sessionHeartbeat ?? device.createKeepalive();
    var started = false;
    try {
      if (!borrowed) await heartbeat.start();
      report(StartupStage.launching);
      device.progress('Starting Pilot with the confirmed time and location…');
      await device.call(
        'start',
        project: project,
        fields: {
          'operation': device.operationId(),
          'site': site.toJson(),
          'epoch': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        },
      );
      started = true;
      report(StartupStage.waiting);
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (true) {
        heartbeat.check();
        final status = await device.call(
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
      device.progress('Handing the controller connection to Pilot…');
      if (borrowed) device._sessionHeartbeat = null;
      await heartbeat.close();
      for (var i = 0; i < 10 && await device.controllers() != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await device.call(
        'connect',
        project: project,
        fields: {'operation': device.operationId()},
      );
      report(StartupStage.verifying);
      final connectedDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(connectedDeadline)) {
        final state = await device.call(
          'inspect',
          project: project,
          timeout: const Duration(seconds: 25),
        );
        report(stage, response: true);
        final pilot = state['pilot'] as Map?;
        if (pilot?['connected'] == true &&
            (pilot?['age517'] as num? ?? 999) < 5) {
          device.progress(
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
          await device.call(
            'stop',
            project: project,
            fields: {'operation': device.operationId()},
          );
          report(stage, cleanup: StartupCleanup.confirmed);
        } catch (_) {
          report(stage, cleanup: StartupCleanup.uncertain);
          device.progress(
            'Cleanup could not be confirmed. Reconnect and inspect the device.',
          );
        }
      }
      rethrow;
    } finally {
      if (identical(device._sessionHeartbeat, heartbeat)) device._sessionHeartbeat = null;
      await heartbeat.close();
    }
  }
