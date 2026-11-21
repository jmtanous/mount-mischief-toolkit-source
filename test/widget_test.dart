import 'ui_test_support.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mount_mischief_toolkit/main.dart';
import 'package:mount_mischief_toolkit/catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class InterruptedSignInCatalog extends Catalog {
  InterruptedSignInCatalog({required super.cacheDirectory});
  final failure = Completer<void>();

  @override
  Future<void> signIn(Future<void> Function(String, Uri) showCode) async {
    await showCode('TEST-CODE', Uri.https('github.com', '/login/device'));
    await failure.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('org.mountmischief/wifi-status'), (_) async => null);
    // Each widget test has a separate fake clock/zone. Do not reuse an asset
    // Future created in a previous test's zone.
    rootBundle.evict('assets/catalog.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null);
  });
  testWidgets('Independent branding, cached catalog, and unpaired state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final temp = Directory.systemTemp.createTempSync('toolkit-widget-');
    addTearDown(() => temp.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        child: ToolkitApp(catalog: Catalog(cacheDirectory: temp)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    expect(find.text('Polaris'), findsWidgets);
    expect(find.text(independence), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'device');
    await tester.tap(find.text('Catalog'));
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    expect(find.text('Alpaca Pilot'), findsOneWidget);
    expect(find.text('Sign in with GitHub'), findsOneWidget);
    await capture(tester, 'catalog');
    await tester.tap(find.text('Installed'));
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Pair and inspect a device to see its projects.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Damaged catalog and credentials still show bundled offline project',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'github_session': '{'});
      final temp = Directory.systemTemp.createTempSync('toolkit-offline-ui-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final catalog = Catalog(cacheDirectory: temp);
      await tester.runAsync(() async {
        await File('${(await catalog.directory).path}/catalog.json')
            .writeAsString('{');
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(child: ToolkitApp(catalog: catalog)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catalog'));
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      await waitForWidget(tester, find.text('Alpaca Pilot'));
      expect(find.text('Alpaca Pilot'), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(find.textContaining('Saved catalog is invalid'), findsOneWidget);
      await capture(tester, 'catalog-offline-recovery');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Interrupted sign-in removes the code and allows retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (_) async => true);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, null);
    });
    final temp = Directory.systemTemp.createTempSync('toolkit-signin-ui-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final catalog = InterruptedSignInCatalog(cacheDirectory: temp);
    await tester.pumpWidget(ToolkitApp(catalog: catalog));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catalog'));
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with GitHub'));
    await waitForWidget(tester, find.text('GitHub code: TEST-CODE'));
    expect(find.text('Cancel sign-in'), findsOneWidget);
    catalog.failure.completeError(const SocketException('Network lost'));
    await waitForWidget(
      tester,
      find.text('GitHub sign-in did not complete. You can try again.'),
    );
    await enterMountWorkspace(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('TEST-CODE'), findsNothing);
    expect(find.text('Cancel sign-in'), findsNothing);
    expect(find.text('Sign in with GitHub'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Revoked catalog access immediately restores the sign-in button',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'github_token': 'test-token'});
      final temp = Directory.systemTemp.createTempSync('toolkit-revoked-ui-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final catalog = Catalog(
        cacheDirectory: temp,
        client: MockClient((_) async => http.Response('', 401)),
      );
      await tester.pumpWidget(ToolkitApp(catalog: catalog));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catalog'));
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      await waitForWidget(tester, find.text('Refresh catalog'));
      expect(find.text('Refresh catalog'), findsOneWidget);
      await tester.tap(find.text('Refresh catalog'));
      await waitForWidget(tester, find.text('Sign in with GitHub'));
      await enterMountWorkspace(tester);
      await tester.pumpAndSettle();
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(find.text('Refresh catalog'), findsNothing);
      expect(find.textContaining('Sign in again'), findsOneWidget);
      expect(find.text('Alpaca Pilot'), findsOneWidget);
    },
  );
}
