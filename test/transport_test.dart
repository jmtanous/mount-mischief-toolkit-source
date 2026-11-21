import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/benro.dart';

class FakeSession implements SSHSession {
  final output = StreamController<Uint8List>();
  final errors = StreamController<Uint8List>();
  final input = StreamController<Uint8List>();
  final completed = Completer<void>();
  bool closed = false;
  int? code = 0;
  @override
  SSHSessionExitSignal? get exitSignal => null;
  final writes = <List<int>>[];
  FakeSession() {
    input.stream.listen(writes.add);
  }
  @override
  Stream<Uint8List> get stdout => output.stream;
  @override
  Stream<Uint8List> get stderr => errors.stream;
  @override
  StreamSink<Uint8List> get stdin => input.sink;
  @override
  Future<void> get done => completed.future;
  @override
  int? get exitCode => code;
  @override
  void write(Uint8List data) {
    writes.add(data);
  }

  @override
  Future<void> flush() async {
    throw StateError('Transport flush must not race the SSH channel writer');
  }

  void finish([String text = 'done']) {
    output.add(Uint8List.fromList(text.codeUnits));
    output.close();
    errors.close();
    if (!completed.isCompleted) completed.complete();
  }

  @override
  void close() {
    closed = true;
    output.close();
    errors.close();
    input.close();
    if (!completed.isCompleted) completed.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClient implements SSHClient {
  final Future<SSHSession> Function() create;
  FakeClient(this.create);
  @override
  Future<SSHSession> execute(
    String command, {
    Map<String, String>? environment,
    SSHPtyConfig? pty,
    SSHX11Config? x11,
  }) => create();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Benro transport(Future<SSHSession> Function() create) => Benro(
  host: '127.0.0.1',
  progress: (_) {},
  confirmKey: (_, _) async => false,
  client: FakeClient(create),
);

void main() {
  test('SSH collects output and closes session', () async {
    final session = FakeSession();
    final device = transport(() async => session);
    scheduleMicrotask(() => session.finish('hello'));
    expect(await device.shell('test'), 'hello');
    expect(session.closed, isTrue);
  });
  test('Upload stalls are covered by the command timeout', () async {
    final session = FakeSession();
    var cancelled = false;
    final stalled = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    stalled.add([1, 2]);
    final device = transport(() async => session);
    await expectLater(
      device.shell(
        'test',
        input: stalled.stream,
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(session.closed, isTrue);
    expect(session.writes.length, 1);
    expect(cancelled, isTrue);
  });
  test('Upload streams all chunks and waits for remote completion without flushing', () async {
    final session = FakeSession();
    final device = transport(() async => session);
    final chunks = [
      [1, 2],
      [3],
      [4, 5, 6],
    ];
    session.input.done.then((_) => session.finish('received'));
    expect(
      await device.shell('cat', input: Stream.fromIterable(chunks)),
      'received',
    );
    expect(session.writes, chunks);
    expect(session.closed, isTrue);
  });
  test('Session arriving after timeout is immediately closed', () async {
    final late = Completer<SSHSession>();
    final device = transport(() => late.future);
    await expectLater(
      device.shell('test', timeout: const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );
    final session = FakeSession();
    late.complete(session);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(session.closed, isTrue);
    expect(session.writes, isEmpty);
  });
  test('Excessive output fails without waiting for other stream', () async {
    final session = FakeSession();
    final device = transport(() async => session);
    scheduleMicrotask(() => session.output.add(Uint8List(2 * 1024 * 1024 + 1)));
    await expectLater(
      device.shell('test', timeout: const Duration(seconds: 1)),
      throwsStateError,
    );
    expect(session.closed, isTrue);
  });
  test('Remote nonzero exit is not reported as success', () async {
    final session = FakeSession()..code = 1;
    final device = transport(() async => session);
    scheduleMicrotask(() => session.finish('failed'));
    await expectLater(device.shell('test'), throwsStateError);
  });
  for (final code in [1, null]) {
    test('Silent failed command reports its exit status ($code)', () async {
      final session = FakeSession()..code = code;
      final device = transport(() async => session);
      scheduleMicrotask(() => session.finish(''));
      await expectLater(
        device.shell('cat > /unused'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'diagnostic',
            'Device command cat failed (exit ${code ?? 'not reported'}). No error output was returned.',
          ),
        ),
      );
    });
  }
}
