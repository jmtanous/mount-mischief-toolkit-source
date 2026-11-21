import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/benro.dart';

void main() {
  test(
    'Heartbeat binds to the phone address reported by authenticated SSH',
    () {
      expect(
        Benro.heartbeatSourceAddress('192.168.0.3 41816 192.168.0.1 22\n')
            .address,
        '192.168.0.3',
      );
      for (final invalid in [
        '',
        '192.168.0.3',
        'bad 41816 192.168.0.1 22',
        '192.168.0.3 bad 192.168.0.1 22',
        '192.168.0.3 41816 bad 22',
      ]) {
        expect(() => Benro.heartbeatSourceAddress(invalid), throwsStateError);
      }
    },
  );
  late ServerSocket server;
  late Keepalive heartbeat;
  final sockets = <Socket>[];
  setUp(() async {
    server = await ServerSocket.bind(InternetAddress('127.0.0.2'), 0);
    heartbeat = Keepalive(
      '127.0.0.2',
      port: server.port,
      sourceAddress: InternetAddress.loopbackIPv4,
    );
  });
  tearDown(() async {
    await heartbeat.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await server.close();
  });

  test('Real socket negotiates context and sends periodic heartbeat', () async {
    final periodic = Completer<void>();
    final accepted = server.first;
    final starting = heartbeat.start();
    final socket = await accepted;
    sockets.add(socket);
    var received = '';
    var replied = false;
    socket.listen((data) {
      received += ascii.decode(data);
      if (!replied && received.contains('1&808&2&type:0;#')) {
        replied = true;
        socket.write('808@ret:');
        socket.flush().then((_) => socket.write('0;#'));
      }
      if (received.contains('h#1&284&2&-1#') && !periodic.isCompleted) {
        socket.write('h#284@ret:0;#');
        periodic.complete();
      }
    });
    await starting;
    expect(socket.remoteAddress.address, '127.0.0.1');
    expect(socket.address.address, '127.0.0.2');
    expect(
      heartbeat.peer,
      '0100007F:${socket.remotePort.toRadixString(16).padLeft(4, '0').toUpperCase()}',
    );
    await periodic.future.timeout(const Duration(seconds: 8));
    heartbeat.check();
    await heartbeat.close();
    expect(heartbeat.peer, isNull);
    expect(heartbeat.check, throwsStateError);
  });

  for (final localClose in [true, false]) {
    test(
      '${localClose ? 'Local' : 'Remote'} close before acknowledgment fails promptly',
      () async {
        final accepted = server.first;
        final starting = expectLater(heartbeat.start(), throwsStateError);
        final socket = await accepted;
        sockets.add(socket);
        await socket.first; // Wait until the context request was actually sent.
        if (localClose) {
          await heartbeat.close();
        } else {
          socket.destroy();
        }
        await starting.timeout(const Duration(seconds: 2));
        expect(heartbeat.peer, isNull);
      },
    );
  }
}
