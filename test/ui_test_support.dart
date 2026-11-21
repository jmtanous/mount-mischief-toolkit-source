import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadTestFonts() async {
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final flutter = (config['packages'] as List).firstWhere(
    (p) => p['name'] == 'flutter',
  ) as Map;
  final fonts = configFile.absolute.uri
      .resolve('${flutter['rootUri']}/')
      .resolve('../../bin/cache/artifacts/material_fonts/');
  for (final font in {
    'Roboto': 'Roboto-Regular.ttf',
    'MaterialIcons': 'MaterialIcons-Regular.otf',
  }.entries) {
    final bytes = File.fromUri(fonts.resolve(font.value)).readAsBytesSync();
    await (FontLoader(
      font.key,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
  for (final family in ['RedHatDisplay', 'RadioCanadaBig']) {
    final bytes = File('assets/fonts/$family.ttf').readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('artifacts/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> waitForWidget(WidgetTester tester, Finder target) async {
  // File and asset I/O may schedule another real operation after a fake-zone
  // microtask. Advance both until the observable screen is ready.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isNotEmpty) return;
  }
  final visible = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .join(' | ');
  fail('Widget did not appear: $target. Screen: $visible');
}

Future<void> enterMountWorkspace(WidgetTester tester) async {
  await tester.pump();
  final accept = find.text('Accept and continue');
  if (find.text('Mount Mischief\nToolkit').evaluate().isEmpty) return;
  final checkbox = find.text(
    'I understand this is experimental software and I accept the risks.',
  );
  await tester.scrollUntilVisible(
    checkbox,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(checkbox);
  await tester.pump();
  await tester.scrollUntilVisible(
    accept,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(accept);
  await tester.pumpAndSettle();
  final choose = find.text('Choose Polaris');
  await tester.ensureVisible(choose);
  await tester.tap(choose);
  await tester.pumpAndSettle();
}

Future<void> expandDiagnosticDetails(WidgetTester tester) async {
  final details = find.text('Details');
  if (details.evaluate().isNotEmpty) {
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
  }
}
