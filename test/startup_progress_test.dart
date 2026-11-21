import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mount_mischief_toolkit/main.dart' show toolkitTheme;
import 'package:mount_mischief_toolkit/startup_progress.dart';

import 'ui_test_support.dart';

void main() {
  setUpAll(loadTestFonts);
  testWidgets(
    'Startup duration note appears while starting and hides during cleanup',
    (tester) async {
      final progress = StartupProgress();
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: toolkitTheme(),
          home: Scaffold(body: StartupProgressCard(progress: progress)),
        ),
      );
      progress.update(const StartupEvent(StartupStage.launching));
      progress.update(
        const StartupEvent(StartupStage.waiting, responseReceived: true),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('Elapsed:'), findsNothing);
      expect(find.textContaining('Last status response:'), findsNothing);
      expect(
        find.text('Alpaca Pilot startup can take up to 3 minutes.'),
        findsOneWidget,
      );
      expect(find.text('Pilot ready'), findsNothing);
      progress.update(
        const StartupEvent(
          StartupStage.waiting,
          cleanup: StartupCleanup.stopping,
        ),
      );
      await tester.pump();
      expect(find.text('Stopping Pilot after startup failed…'), findsOneWidget);
      expect(
        find.text('Alpaca Pilot startup can take up to 3 minutes.'),
        findsNothing,
      );
      progress.update(
        const StartupEvent(
          StartupStage.waiting,
          cleanup: StartupCleanup.uncertain,
        ),
      );
      progress.finish(error: 'Connection lost');
      await tester.pump();
      expect(progress.stage, StartupStage.waiting);
      expect(find.text('Pilot startup failed'), findsOneWidget);
      expect(
        find.text('Alpaca Pilot startup can take up to 3 minutes.'),
        findsNothing,
      );
      expect(
        find.text(
          'Cleanup unconfirmed. Reconnect and inspect before retrying.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('Elapsed:'), findsNothing);
    },
  );

  testWidgets(
    'Success waits for finish and existing process is not called ready',
    (tester) async {
      final progress = StartupProgress();
      addTearDown(progress.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartupProgressCard(progress: progress)),
        ),
      );
      for (final stage in StartupStage.values) {
        progress.update(StartupEvent(stage));
      }
      await tester.pump();
      expect(find.text('Pilot ready'), findsNothing);
      progress.finish();
      await tester.pump();
      expect(find.text('Pilot ready'), findsOneWidget);
      expect(
        find.text('Alpaca Pilot startup can take up to 3 minutes.'),
        findsNothing,
      );
      expect(progress.completed, containsAll(StartupStage.values));
      final existing = StartupProgress();
      addTearDown(existing.dispose);
      existing.update(
        const StartupEvent(StartupStage.verifying, alreadyRunning: true),
      );
      existing.finish();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartupProgressCard(progress: existing)),
        ),
      );
      expect(find.text('Pilot was already running'), findsOneWidget);
      expect(find.text('Pilot ready'), findsNothing);
    },
  );

  testWidgets('Reduced motion keeps the checklist static', (tester) async {
    final progress = StartupProgress();
    addTearDown(progress.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: StartupProgressCard(progress: progress)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Alpaca Pilot startup can take up to 3 minutes.'),
      findsOneWidget,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Progress card fits a phone with large text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final progress = StartupProgress();
    addTearDown(progress.dispose);
    progress.update(const StartupEvent(StartupStage.launching));
    progress.update(
      const StartupEvent(StartupStage.waiting, responseReceived: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: toolkitTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.6),
          ),
          child: RepaintBoundary(
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    StartupProgressCard(progress: progress),
                    const Expanded(
                      child: SingleChildScrollView(
                        child: SizedBox(
                          height: 1200,
                          child: Text('Installed projects'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    await capture(tester, 'pilot-startup-large-text');
  });
}
