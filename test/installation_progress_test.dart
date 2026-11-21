import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mount_mischief_toolkit/installation_progress.dart';

void main() {
  test('failure retains stage and rejects late completion events', () {
    final p = InstallationProgress('Installing Pilot');
    p.update(const InstallationEvent('extract', done: 4, total: 10));
    p.finish(error: StateError('Connection lost'));
    p.update(const InstallationEvent('activate'));
    p.finish();
    expect(p.stage, 'extract');
    expect(p.completed.contains('extract'), isFalse);
    expect(p.failure, contains('Connection lost'));
    p.dispose();
  });
  testWidgets('shows file counts and no fabricated overall percentage', (
    tester,
  ) async {
    final p = InstallationProgress('Installing Pilot');
    p.update(const InstallationEvent('verify', done: 12, total: 40));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InstallationProgressCard(progress: p)),
      ),
    );
    expect(find.text('12 / 40 files'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .3,
    );
    p.update(const InstallationEvent('activate'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    p.finish();
    await tester.pump();
    expect(find.text('Installation complete'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });
}
