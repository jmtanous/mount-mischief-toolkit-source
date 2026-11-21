import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mount_mischief_toolkit/entry_flow.dart';
import 'package:mount_mischief_toolkit/main.dart' show toolkitTheme;

import 'ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);
  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Widget app({Key? key, VoidCallback? onWorkspace}) => MaterialApp(
    theme: toolkitTheme(),
    home: RepaintBoundary(
      child: EntryFlow(
        key: key,
        workspace: (change) {
          onWorkspace?.call();
          return Scaffold(
            body: TextButton(
              onPressed: change,
              child: const Text('Change mount'),
            ),
          );
        },
      ),
    ),
  );

  testWidgets(
    'Acknowledgment and model choice are required before creating workspace',
    (tester) async {
      var created = 0;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(onWorkspace: () => created++));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'welcome-stitch');
      await scrollTo(tester, 'Accept and continue');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Accept and continue'),
            )
            .onPressed,
        isNull,
      );
      expect(created, 0);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Accept and continue'));
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(find.text('Choose your mount'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'mount-chooser-stitch');
      await scrollTo(tester, 'Choose Polaris');
      await tester.tap(find.text('Choose Polaris'));
      await tester.pumpAndSettle();
      expect(created, 1);
      await tester.tap(find.text('Change mount'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your mount'), findsOneWidget);
      expect(find.text('Accept and continue'), findsNothing);
    },
  );

  testWidgets(
    'Returning from Android does not reset gate but cold state does',
    (tester) async {
      await tester.pumpWidget(app(key: const ValueKey(1)));
      await enterMountWorkspace(tester);
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
      await tester.pumpAndSettle();
      expect(find.text('Change mount'), findsOneWidget);
      await tester.pumpWidget(app(key: const ValueKey(2)));
      await tester.pumpAndSettle();
      expect(find.text('Mount Mischief\nToolkit'), findsOneWidget);
    },
  );

  testWidgets(
    'About support and licenses work with large text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: toolkitTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const RepaintBoundary(child: ToolkitAbout()),
        ),
      );
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Buy me a beer');
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Buy me a beer'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await scrollTo(tester, 'Open-source licenses');
      await tester.tap(find.text('Open-source licenses'));
      await tester.pumpAndSettle();
      expect(find.text('Licenses'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('About & support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Exit closes app without creating workspace', (tester) async {
    var created = false;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(app(onWorkspace: () => created = true));
    await scrollTo(tester, 'Get me out of here');
    await tester.tap(find.text('Get me out of here'));
    await tester.pump();
    expect(calls, contains('SystemNavigator.pop'));
    expect(created, isFalse);
  });

  testWidgets('Unconfigured support cannot launch a payment page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SupportButton(url: '')),
      ),
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Buy me a beer'))
          .onPressed,
      isNull,
    );
    expect(find.text('Tip jar coming soon'), findsOneWidget);
  });

  testWidgets(
    'Configured beer link opens the creator page in an external browser',
    (tester) async {
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      Map<dynamic, dynamic>? launched;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            launched = call.arguments as Map;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, null),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SupportButton())),
      );
      await tester.tap(find.text('Buy me a beer'));
      await tester.pumpAndSettle();
      expect(launched?['url'], 'https://buymeacoffee.com/jmtanousk');
      expect(launched?['useWebView'], isFalse);
      expect(find.textContaining('Internet required'), findsOneWidget);
    },
  );

  test('Support destination accepts only configured HTTPS creator pages', () {
    expect(
      supportDestination('https://buymeacoffee.com/example')?.path,
      '/example',
    );
    for (final url in [
      '',
      'https://buymeacoffee.com',
      'http://buymeacoffee.com/example',
      'https://evil.example/creator',
      'https://someone@buymeacoffee.com/creator',
    ]) {
      expect(supportDestination(url), isNull);
    }
  });

  testWidgets('Welcome remains usable on narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: EntryFlow(workspace: (_) => const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, 'Accept and continue');
    expect(tester.takeException(), isNull);
  });
}
