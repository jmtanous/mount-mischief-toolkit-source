import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_channel.dart';
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
  late final StreamSubscription<Uint8List> inputSubscription;
  FakeSession() {
    inputSubscription = input.stream.listen(writes.add);
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
  test(
    'stderr progress streams before command completion across UTF8 chunks',
    () async {
      final session = FakeSession();
      final device = transport(() async => session);
      final lines = <String>[];
      final result = device.shell('test', onStderrLine: lines.add);
      final bytes = utf8.encode('Unpacking…\nnext\n');
      session.errors.add(Uint8List.fromList(bytes.sublist(0, 10)));
      session.errors.add(Uint8List.fromList(bytes.sublist(10)));
      await Future<void>.delayed(Duration.zero);
      expect(lines, ['Unpacking…', 'next']);
      expect(session.completed.isCompleted, isFalse);
      session.finish('result');
      expect(await result, 'result');
    },
  );
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
  test('Large upload yields to UI events and bounds individual writes', () async {
    final session = FakeSession();
    final device = transport(() async => session);
    final payload = Uint8List.fromList(List.generate(256 * 1024, (i) => i % 251));
    var finishedWriting = false;
    var eventRanDuringUpload = false;
    session.input.done.then((_) {
      finishedWriting = true;
      session.finish('received');
    });
    Timer.run(() => eventRanDuringUpload = !finishedWriting);
    expect(await device.shell('cat', input: Stream.value(payload)), 'received');
    await Future<void>.delayed(Duration.zero);
    expect(eventRanDuringUpload, isTrue);
    expect(session.writes.every((chunk) => chunk.length <= 16 * 1024), isTrue);
    expect(session.writes.expand((chunk) => chunk), payload);
  });
  test('Paused SSH stdin applies backpressure to the upload source', () async {
    final session = FakeSession();
    session.inputSubscription.pause();
    final device = transport(() async => session);
    var read = 0;
    final source = Stream.fromIterable(List.generate(32, (_) => [1, 2, 3]))
        .map((chunk) { read++; return chunk; });
    session.input.done.then((_) => session.finish('received'));
    final result = device.shell('cat', input: source);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(read, lessThanOrEqualTo(1));
    session.inputSubscription.resume();
    expect(await result, 'received');
    expect(read, 32);
    expect(session.writes.expand((chunk) => chunk), List.generate(96, (i) => i % 3 + 1));
  });
  test('Upload timeout also cancels a backpressured source', () async {
    late SSHChannelController channel;
    channel = SSHChannelController(
      localId: 0, remoteId: 1,
      localInitialWindowSize: 32768, localMaximumPacketSize: 32768,
      remoteInitialWindowSize: 0, remoteMaximumPacketSize: 32768,
      sendMessage: (message) {
        if (message is SSH_Message_Channel_EOF) {
          scheduleMicrotask(() => channel.handleMessage(
            SSH_Message_Channel_Close(recipientChannel: 0),
          ));
        }
      },
    );
    final session = SSHSession(channel.channel);
    final device = transport(() async => session);
    await expectLater(
      device.shell('cat', input: Stream.value([1, 2, 3]),
        timeout: const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );
    await session.done.timeout(const Duration(seconds: 1));
  });
  test('Real SSH session stops reading at a closed remote window and resumes intact', () async {
    final received = <int>[];
    late SSHChannelController channel;
    channel = SSHChannelController(
      localId: 0, remoteId: 1,
      localInitialWindowSize: 32768, localMaximumPacketSize: 32768,
      remoteInitialWindowSize: 0, remoteMaximumPacketSize: 32768,
      sendMessage: (message) {
        if (message is SSH_Message_Channel_Data) received.addAll(message.data);
        if (message is SSH_Message_Channel_EOF) {
          scheduleMicrotask(() {
            channel.handleMessage(SSH_Message_Channel_Request.exitStatus(
              recipientChannel: 0, exitStatus: 0,
            ));
            channel.handleMessage(SSH_Message_Channel_Data(
              recipientChannel: 0, data: Uint8List.fromList('received'.codeUnits),
            ));
            channel.handleMessage(SSH_Message_Channel_EOF(recipientChannel: 0));
            channel.handleMessage(SSH_Message_Channel_Close(recipientChannel: 0));
          });
        }
      },
    );
    final session = SSHSession(channel.channel);
    final device = transport(() async => session);
    final payload = Uint8List.fromList(List.generate(128 * 1024, (i) => i % 251));
    var sourceChunks = 0;
    final source = Stream.fromIterable([
      for (var offset = 0; offset < payload.length; offset += 16384)
        payload.sublist(offset, offset + 16384),
    ]).map((chunk) { sourceChunks++; return chunk; });
    final result = device.shell('cat', input: source);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received, isEmpty);
    expect(sourceChunks, lessThanOrEqualTo(1));
    channel.handleMessage(SSH_Message_Channel_Window_Adjust(
      recipientChannel: 0, bytesToAdd: 16384,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(received, payload.sublist(0, 16384));
    expect(sourceChunks, lessThanOrEqualTo(2));
    channel.handleMessage(SSH_Message_Channel_Window_Adjust(
      recipientChannel: 0, bytesToAdd: payload.length,
    ));
    expect(await result, 'received');
    expect(received, payload);
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
