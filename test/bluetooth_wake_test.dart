import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mount_mischief_toolkit/bluetooth_wake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showBluetoothWake(context),
              child: const Text('Wake'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Wake'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'bluetooth_mount': 'BB'});
    calls = [];
    handler = (call) async => call.method == 'bluetoothScan'
        ? [
            {'name': 'polaris_a', 'address': 'AA'},
            {'name': 'polaris_b', 'address': 'BB'},
          ]
        : null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(wakeChannel, (call) {
          calls.add(call);
          return handler(call);
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(wakeChannel, null),
  );

  testWidgets(
    'Discovery requires explicit selection, remembers choice and releases BLE',
    (tester) async {
      await open(tester);
      expect(calls.where((c) => c.method == 'bluetoothWake'), isEmpty);
      expect(find.textContaining('Previous selection'), findsOneWidget);
      await tester.tap(find.text('polaris_a'));
      await tester.pumpAndSettle();
      expect(calls.singleWhere((c) => c.method == 'bluetoothWake').arguments, {
        'address': 'AA',
      });
      expect(
        (await SharedPreferences.getInstance()).getString('bluetooth_mount'),
        'AA',
      );
      expect(calls.last.method, 'bluetoothCancel');
    },
  );
  testWidgets('Empty scan permits bounded explicit rescan without waking', (
    tester,
  ) async {
    handler = (_) async => [];
    await open(tester);
    expect(find.textContaining('No Polaris found'), findsOneWidget);
    await tester.tap(find.text('Scan again'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'bluetoothScan').length, 2);
    expect(calls.where((c) => c.method == 'bluetoothWake'), isEmpty);
  });
  for (final code in ['BLE_PERMISSION', 'BLE_DISABLED', 'BLE_TIMEOUT']) {
    testWidgets('$code displays recovery without automatic retry', (
      tester,
    ) async {
      handler = (_) async =>
          throw PlatformException(code: code, message: 'Try settings');
      await open(tester);
      expect(find.text('Try settings'), findsOneWidget);
      expect(find.text('App permissions'), findsOneWidget);
      expect(calls.where((c) => c.method == 'bluetoothScan').length, 1);
    });
  }
  testWidgets(
    'Cancel during scan ignores late results and closes native resources',
    (tester) async {
      final pending = Completer<Object?>();
      handler = (c) =>
          c.method == 'bluetoothScan' ? pending.future : Future.value(null);
      await tester.pumpWidget(const MaterialApp(home: BluetoothWakeDialog()));
      await tester.pump();
      // Dispose the route while the native operation is still pending.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      pending.complete([
        {'name': 'polaris_late', 'address': 'CC'},
      ]);
      await tester.pump();
      expect(calls.any((c) => c.method == 'bluetoothCancel'), isTrue);
      expect(calls.any((c) => c.method == 'bluetoothWake'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
