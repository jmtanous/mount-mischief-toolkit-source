import 'ui_test_support.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mount_mischief_toolkit/benro.dart';
import 'package:mount_mischief_toolkit/startup_progress.dart';
import 'package:mount_mischief_toolkit/catalog.dart';
import 'package:mount_mischief_toolkit/main.dart';
import 'package:mount_mischief_toolkit/models.dart';

class OfflineCatalog extends Catalog {
  final ProjectManifest project;
  OfflineCatalog(Directory cache, this.project) : super(cacheDirectory: cache);
  @override
  Future<bool> get signedIn async => false;
  @override
  Future<List<ProjectManifest>> cached() async => [project];
  @override
  Future<bool> available(ProjectManifest manifest) async => true;
  @override
  Future<File> bundled(ProjectManifest manifest) async =>
      File('${cacheDirectory!.path}/fixture.tar.gz');
  @override
  Future<File> bootstrap() => bundled(project);
}

class ManagedDevice extends Benro {
  final ProjectManifest project;
  final List<String> events;
  bool installed = true;
  bool running = true;
  bool incomplete = false;
  bool retained = false;
  bool failUninstall = false;
  bool failStart = false;
  bool failInspect = false;
  bool failRepair = false;
  bool closed = false;
  @override
  bool get holdingHeartbeat => !closed && !running;
  @override
  void close() {
    closed = true;
    super.close();
  }

  Site? startedSite;
  int inspections = 0;
  Map<String, dynamic> settings = {};
  ManagedDevice(this.project, this.events)
    : super(
        host: deviceHost,
        progress: (_) {},
        confirmKey: (_, _) async => true,
      );
  @override
  Future<void> open() async {
    closed = false;
    events.add('open');
  }

  @override
  Future<bool> hasToolchain() async => true;
  @override
  Future<Map<String, dynamic>> inspect() async {
    inspections++;
    if (failInspect) throw const SocketException('connection lost');
    return {
      'controller_clients': running ? 1 : 0,
      'setup_incomplete': incomplete,
      'operations': [],
      'projects': [
        if (installed && !incomplete)
          {
            'id': project.id,
            'installation': {'manifest': project.json},
            'running': running,
            'settings': settings,
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> start(
    String project,
    Site site, {
    void Function(StartupEvent)? onProgress,
  }) async {
    events.add('start');
    startedSite = site;
    if (failStart) throw const SocketException('connection lost during start');
    running = true;
    return {'running': true};
  }

  @override
  Future<Map<String, dynamic>> call(
    String op, {
    String? project,
    Map<String, dynamic> fields = const {},
    Duration timeout = const Duration(minutes: 5),
  }) async => {'retained_settings': retained};
  @override
  Future<void> stop(String project) async {
    events.add('stop');
    running = false;
  }

  @override
  Future<void> uninstall(String project, bool keepSettings) async {
    events.add('uninstall:$keepSettings');
    if (failUninstall) throw const SocketException('connection lost');
    installed = false;
  }

  @override
  Future<void> install(
    ProjectManifest manifest,
    File archive,
    File bootstrap, {
    bool reinstall = false,
    bool keepSettings = true,
  }) async {
    events.add('install:$reinstall:$keepSettings');
    installed = true;
  }

  @override
  Future<void> repairSetup(File bootstrap) async {
    events.add('repair');
    if (failRepair) {
      throw const SocketException('connection lost during repair');
    }
    incomplete = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);
  late Directory temp;
  late ProjectManifest project;
  late List<String> events;
  late ManagedDevice device;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.mountmischief/wifi-status'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('mmt-workflow-');
    project = ProjectManifest(
      Map<String, dynamic>.from(
        jsonDecode(
              File('assets/catalog.json').readAsStringSync(),
            )['projects'][0]
            as Map,
      ),
    );
    events = [];
    device = ManagedDevice(project, events);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          events.add('platform:${call.method}');
          if (call.method == 'keepAwake') {
            events.add('platform:awake:${call.arguments}');
          }
          return null;
        });
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });

  Future<void> open(WidgetTester tester, {String page = 'Installed'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        child: ToolkitApp(
          catalog: OfflineCatalog(temp, project),
          deviceFactory: (_, _, _) => device,
        ),
      ),
    );
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pair and inspect'));
    await tester.tap(find.text('Pair and inspect'));
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    if (page != 'Device') {
      await tester.tap(find.text(page));
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
    }
    events.clear();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // A confirmation leaves the busy indicator animating behind the dialog.
    // Allow asset I/O and the dialog transition without waiting for that spinner.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 500));
        await expandDiagnosticDetails(tester);
        return;
      }
    }
    fail('Workflow did not reach a confirmation or completion: $events');
  }

  Future<void> enterSite(WidgetTester tester, List<String> values) async {
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }
  }

  Future<void> openGuide(WidgetTester tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        child: ToolkitApp(
          catalog: OfflineCatalog(temp, project),
          deviceFactory: (_, _, _) => device,
        ),
      ),
    );
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
  }

  void expectPrimary(WidgetTester tester, String label) {
    for (final name in ['Wake Wi-Fi', 'Wi-Fi settings', 'Pair and inspect']) {
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, name),
      );
      expect(
        button.style!.backgroundColor!.resolve({}),
        name == label ? const Color(0xffcabeff) : const Color(0xff2b2933),
      );
    }
  }

  void resumeSettings(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  testWidgets(
    'Wi-Fi indicator follows association changes without claiming pairing',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            platform,
            (call) async => call.method == 'wifiStatus'
                ? {'state': 'polaris', 'ssid': 'polaris_test'}
                : null,
          );
      await openGuide(tester);
      expect(find.text('Connected to polaris_test'), findsOneWidget);
      expect(find.text('Connected and ready'), findsNothing);
      Future<void> emit(Map<String, String> value) async {
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'org.mountmischief/wifi-status',
          const StandardMethodCodec().encodeSuccessEnvelope(value),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await emit({'state': 'other'});
      expect(find.text('Connected to polaris_test'), findsNothing);
      expect(find.text('Connected to another Wi-Fi network'), findsOneWidget);
      await emit({'state': 'disconnected'});
      expect(find.text('Not connected to Wi-Fi'), findsOneWidget);
      await emit({'state': 'unknown'});
      expect(
        find.text('Wi-Fi name unavailable — verify by pairing'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Guide advances only after settings launch and return, then resets on disconnect',
    (tester) async {
      await openGuide(tester);
      expectPrimary(tester, 'Wake Wi-Fi');
      await tap(tester, 'Wi-Fi settings');
      expectPrimary(tester, 'Wake Wi-Fi');
      expect(find.text('Ready to check'), findsNothing);
      resumeSettings(tester);
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Pair and inspect');
      expect(find.text('Verify by pairing'), findsOneWidget);
      expect(find.text('Ready to check'), findsOneWidget);
      expect(find.text('Connected and ready'), findsNothing);
      await tap(tester, 'Pair and inspect');
      expect(find.text('Connected and ready'), findsOneWidget);
      await tap(tester, 'Disconnect');
      expectPrimary(tester, 'Wake Wi-Fi');
      expect(find.text('Ready to check'), findsNothing);
    },
  );

  testWidgets(
    'Settings launch failure and unrelated resume do not advance the guide',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            if (call.method == 'wifiSettings') {
              throw PlatformException(code: 'FAILED');
            }
            return null;
          });
      await openGuide(tester);
      resumeSettings(tester);
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Wake Wi-Fi');
      await tap(tester, 'Wi-Fi settings');
      resumeSettings(tester);
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Wi-Fi settings');
      expect(find.text('Could not open Wi-Fi settings'), findsOneWidget);
      expect(find.text('Ready to check'), findsNothing);
    },
  );

  testWidgets(
    'Wake cancellation restores guidance and a failed wake offers retry',
    (tester) async {
      var failWake = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            if (call.method == 'bluetoothScan') {
              return [
                {'name': 'polaris_test', 'address': 'AA'},
              ];
            }
            if (call.method == 'bluetoothWake' && failWake) {
              throw PlatformException(code: 'WAKE_FAILED');
            }
            return null;
          });
      await openGuide(tester);
      await tap(tester, 'Wi-Fi settings');
      resumeSettings(tester);
      await tester.pumpAndSettle();
      await tap(tester, 'Wake Wi-Fi');
      await tap(tester, 'Cancel');
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Pair and inspect');
      expect(find.text('Wake request completed'), findsNothing);
      failWake = true;
      await tap(tester, 'Wake Wi-Fi');
      await tap(tester, 'polaris_test');
      await tap(tester, 'Cancel');
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Wake Wi-Fi');
      expect(find.text('Wake failed'), findsOneWidget);
      expect(find.text('Wake request completed'), findsNothing);
    },
  );

  testWidgets(
    'Wake completion highlights Wi-Fi settings; Later does not imply a connection',
    (tester) async {
      final wakeResult = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            if (call.method == 'bluetoothScan') {
              return [
                {'name': 'polaris_test', 'address': 'AA'},
              ];
            }
            if (call.method == 'bluetoothWake') await wakeResult.future;
            return null;
          });
      await openGuide(tester);
      await tap(tester, 'Wake Wi-Fi');
      await tap(tester, 'polaris_test');
      expect(find.text('Waking Wi-Fi…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Pair and inspect'),
            )
            .onPressed,
        isNull,
      );
      wakeResult.complete();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tap(tester, 'Later');
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Wi-Fi settings');
      expect(find.text('Wake request completed'), findsOneWidget);
      expect(find.text('Ready to check'), findsNothing);
      expect(find.text('Connected and ready'), findsNothing);
      await capture(tester, 'connection-guide-wake-complete');
    },
  );

  testWidgets(
    'Unreachable pairing offers wake, joins Wi-Fi, then retries normal pairing',
    (tester) async {
      var missingWifi = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            events.add('platform:${call.method}');
            if (call.method == 'bindWifi' && missingWifi) {
              throw PlatformException(code: 'NO_WIFI', message: 'Join Wi-Fi');
            }
            if (call.method == 'bluetoothScan') {
              return [
                {'name': 'polaris_test', 'address': 'AA'},
              ];
            }
            if (call.method == 'wifiSettings') missingWifi = false;
            return null;
          });
      await tester.pumpWidget(
        ToolkitApp(
          catalog: OfflineCatalog(temp, project),
          deviceFactory: (_, _, _) => device,
        ),
      );
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      await tap(tester, 'Pair and inspect');
      expect(find.text('Cannot reach Polaris'), findsOneWidget);
      expect(events.contains('open'), isFalse);
      await tap(tester, 'Wake Wi-Fi and retry');
      await tester.pump(const Duration(seconds: 1));
      await tap(tester, 'polaris_test');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Join Polaris Wi-Fi'), findsOneWidget);
      expect(events.contains('open'), isFalse);
      final joinDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(joinDialog.actions, hasLength(2));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Later'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Pair and inspect'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Wi-Fi settings'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Join Polaris Wi-Fi'), findsNothing);
      resumeSettings(tester);
      await tester.pumpAndSettle();
      expectPrimary(tester, 'Pair and inspect');
      expect(events.contains('open'), isFalse);
      await tap(tester, 'Pair and inspect');
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(events.where((e) => e == 'open').length, 1);
      expect(device.inspections, 1);
    },
  );

  testWidgets(
    'Fingerprint and other non-network failures never offer Bluetooth wake',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, (call) async {
            if (call.method == 'bindWifi') {
              throw StateError('SSH fingerprint changed');
            }
            return null;
          });
      await tester.pumpWidget(
        ToolkitApp(
          catalog: OfflineCatalog(temp, project),
          deviceFactory: (_, _, _) => device,
        ),
      );
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      await tap(tester, 'Pair and inspect');
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(find.text('Wake Wi-Fi and retry'), findsNothing);
      expect(find.textContaining('SSH fingerprint changed'), findsOneWidget);
    },
  );

  testWidgets(
    'Changing mounts releases pairing but never stops running Pilot',
    (tester) async {
      await open(tester, page: 'Device');
      await tester.tap(find.byTooltip('Change mount'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(device.closed, isFalse);
      await tester.tap(find.byTooltip('Change mount'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.widgetWithText(FilledButton, 'Change mount'));
      await tester.pumpAndSettle();
      expect(device.closed, isTrue);
      expect(device.running, isTrue);
      expect(events, isNot(contains('stop')));
      expect(events, contains('platform:releaseNetwork'));
      expect(find.text('Choose your mount'), findsOneWidget);
      expect(find.text('Accept and continue'), findsNothing);
    },
  );

  testWidgets(
    'Start cancellation and invalid coordinates never contact device',
    (tester) async {
      device.running = false;
      await open(tester);
      await tap(tester, 'Start');
      await tap(tester, 'Cancel');
      expect(find.byType(StartupProgressCard), findsNothing);
      expect(events.where((e) => !e.startsWith('platform:')), isEmpty);
      await tap(tester, 'Start');
      for (final latitude in ['NaN', '91', 'not a number']) {
        await enterSite(tester, ['Field', latitude, '-99.1', '2200']);
        await tap(tester, 'Confirm and start');
        expect(
          find.text('Enter a site name and valid numeric coordinates.'),
          findsOneWidget,
        );
        expect(device.startedSite, isNull);
        expect(device.running, isFalse);
      }
      await tap(tester, 'Cancel');
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('Start reviews saved site and sends only confirmed values', (
    tester,
  ) async {
    device.running = false;
    device.settings = {
      'location': 'Saved field',
      'site_latitude': 19.4,
      'site_longitude': -99.1,
      'site_elevation': 2200,
    };
    await open(tester);
    await tap(tester, 'Start');
    expect(find.text('Saved field'), findsOneWidget);
    expect(find.text('19.4'), findsOneWidget);
    expect(device.startedSite, isNull);
    await enterSite(tester, ['New field', '-33.9', '151.2', '50']);
    await tester.pump();
    await capture(tester, 'observing-site-confirmation');
    await tap(tester, 'Confirm and start');
    expect(device.startedSite!.toJson(), {
      'name': 'New field',
      'latitude': -33.9,
      'longitude': 151.2,
      'elevation': 50.0,
    });
    expect(
      events.indexOf('platform:bindWifi'),
      lessThan(events.indexOf('start')),
    );
    expect(find.text('Running'), findsOneWidget);
    await capture(tester, 'installed-stitch-live-design');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Start connection loss removes stale state until reinspection', (
    tester,
  ) async {
    device.running = false;
    device.failStart = true;
    await open(tester);
    await tap(tester, 'Start');
    await enterSite(tester, ['Field', '19.4', '-99.1', '2200']);
    await tap(tester, 'Confirm and start');
    expect(find.textContaining('connection lost during start'), findsWidgets);
    expect(find.text('Pilot startup failed'), findsOneWidget);
    expect(find.text('Pilot ready'), findsNothing);
    expect(find.text('Running'), findsNothing);
    expect(
      find.text('Pair and inspect a device to see its projects.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'Open Pilot uses Wi-Fi and in-app webview, returning keeps Stop available',
    (tester) async {
      await open(tester);
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      Map<dynamic, dynamic>? launched;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            launched = call.arguments as Map;
            events.add('browser');
            for (final state in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, null),
      );
      await tap(tester, 'Open Pilot');
      expect(launched?['url'], 'http://192.168.0.1:8081');
      expect(launched?['useWebView'], isTrue);
      expect(launched?['enableJavaScript'], isTrue);
      expect(launched?['enableDomStorage'], isTrue);
      expect(
        events.indexOf('platform:bindWifi'),
        lessThan(events.indexOf('browser')),
      );
      expect(device.closed, isFalse);
      final before = device.inspections;
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(device.inspections, before + 1);
      expect(find.text('Stop'), findsOneWidget);
      expect(
        find.text('Pair and inspect a device to see its projects.'),
        findsNothing,
      );
      await tap(tester, 'Stop');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Stop'),
        ),
      );
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(device.running, isFalse);
      expect(find.text('Start'), findsOneWidget);
    },
  );

  testWidgets('Stopped Pilot cannot open a blank browser', (tester) async {
    device.running = false;
    await open(tester);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Open Pilot'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('Start Pilot before opening its interface.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'A lost session after returning from Pilot still requires fresh pairing',
    (tester) async {
      await open(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(device.closed, isFalse);
      device.failInspect = true;
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(device.closed, isTrue);
      await expandDiagnosticDetails(tester);
      expect(find.textContaining('connection lost'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
    },
  );

  testWidgets('Background closes session; returning requires fresh pairing', (
    tester,
  ) async {
    device.running = false;
    await open(tester, page: 'Device');
    expect(find.textContaining('Keeping Wi-Fi awake'), findsOneWidget);
    final before = device.inspections;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    expect(device.closed, isTrue);
    expect(device.inspections, before);
    expect(find.text('Disconnect'), findsNothing);
    expect(events, contains('platform:awake:false'));
    await tap(tester, 'Pair and inspect');
    expect(device.inspections, before + 1);
    expect(device.closed, isFalse);
    expect(
      events.lastWhere((e) => e.startsWith('platform:awake:')),
      'platform:awake:true',
    );
    await tap(tester, 'Disconnect');
    expect(device.closed, isTrue);
    expect(find.text('Disconnect'), findsNothing);
    expect(
      events.lastWhere((e) => e.startsWith('platform:awake:')),
      'platform:awake:false',
    );
  });

  testWidgets(
    'Repair connection loss closes session and removes stale repair action',
    (tester) async {
      device.running = false;
      device.incomplete = true;
      device.failRepair = true;
      await open(tester, page: 'Device');
      await tap(tester, 'Repair Toolkit setup');
      await tap(tester, 'Repair setup');
      expect(
        find.textContaining('connection lost during repair'),
        findsOneWidget,
      );
      expect(find.textContaining('Rejoin the device Wi-Fi'), findsOneWidget);
      expect(device.closed, isTrue);
      expect(find.text('Repair Toolkit setup'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
      expect(
        events.lastWhere((e) => e.startsWith('platform:awake:')),
        'platform:awake:false',
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('connection lost during repair'),
        findsOneWidget,
      );
    },
  );

  for (final operation in ['Reinstall', 'Uninstall']) {
    testWidgets('$operation cancel preserves running project', (tester) async {
      await open(tester);
      await tap(tester, operation);
      expect(
        find.textContaining('This will stop the managed project first.'),
        findsOneWidget,
      );
      if (operation == 'Reinstall') await capture(tester, 'settings-choice');
      await tap(tester, 'Cancel');
      expect(find.byType(StartupProgressCard), findsNothing);
      expect(events.where((e) => !e.startsWith('platform:')), isEmpty);
      expect(device.running, isTrue);
      expect(device.installed, isTrue);
    });
    for (final keep in [true, false]) {
      testWidgets(
        '$operation explicitly ${keep ? 'keeps' : 'deletes'} settings after stop',
        (tester) async {
          await open(tester);
          await tap(tester, operation);
          await tap(tester, keep ? 'Keep settings' : 'Delete settings');
          expect(events.where((e) => !e.startsWith('platform:')).toList(), [
            'stop',
            operation == 'Reinstall' ? 'install:true:$keep' : 'uninstall:$keep',
          ]);
          expect(
            events.indexOf('platform:bindWifi'),
            lessThan(events.indexOf('stop')),
          );
          expect(device.running, isFalse);
          expect(device.installed, operation == 'Reinstall');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'Stop requires confirmation and cancellation leaves project running',
    (tester) async {
      await open(tester);
      await tap(tester, 'Stop');
      await tap(tester, 'Cancel');
      expect(device.running, isTrue);
      await tap(tester, 'Stop');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Stop'),
        ),
      );
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(device.running, isFalse);
      expect(events.where((e) => e == 'stop'), hasLength(1));
    },
  );
  testWidgets('Connection loss removes stale successful installation state', (
    tester,
  ) async {
    device.failUninstall = true;
    await open(tester);
    await tap(tester, 'Uninstall');
    await tap(tester, 'Keep settings');
    expect(find.textContaining('connection lost'), findsOneWidget);
    expect(
      find.text('Pair and inspect a device to see its projects.'),
      findsOneWidget,
    );
    expect(find.text('Project uninstalled.'), findsNothing);
    expect(device.installed, isTrue);
  });
  testWidgets('Reinstalling a removed project asks about retained settings', (
    tester,
  ) async {
    device.installed = false;
    device.running = false;
    device.retained = true;
    await open(tester, page: 'Catalog');
    await tap(tester, 'Install');
    expect(
      find.textContaining('Install with retained settings for'),
      findsOneWidget,
    );
    expect(events.where((e) => e.startsWith('install:')), isEmpty);
    await tap(tester, 'Delete settings');
    expect(events, contains('install:false:false'));
  });
  testWidgets(
    'Incomplete setup has explicit cancellable repair and restores project inspection',
    (tester) async {
      device.incomplete = true;
      device.running = false;
      await open(tester, page: 'Device');
      expect(
        find.textContaining('Restore MMT’s supporting tools'),
        findsOneWidget,
      );
      expect(find.textContaining('0 managed projects'), findsNothing);
      await capture(tester, 'setup-repair-required');
      await tap(tester, 'Repair Toolkit setup');
      await capture(tester, 'setup-repair-confirmation');
      await tap(tester, 'Cancel');
      expect(events, isNot(contains('repair')));
      await tap(tester, 'Repair Toolkit setup');
      await tap(tester, 'Repair setup');
      expect(events.where((e) => e == 'repair'), hasLength(1));
      expect(find.textContaining('1 managed projects'), findsOneWidget);
      expect(find.text('Repair Toolkit setup'), findsNothing);
      expect(device.installed, isTrue);
    },
  );
}
