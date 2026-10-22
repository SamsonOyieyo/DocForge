import 'package:docforge/app.dart';
import 'package:docforge/core/app_state.dart';
import 'package:docforge/features/settings/settings_page.dart';
import 'package:docforge/features/tool/tool_page.dart';
import 'package:docforge/features/tool/tool_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell renders at desktop and phone widths', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DocForgeApp(state: AppState()));
    await tester.pumpAndSettle();

    expect(find.text('DocForge'), findsWidgets);
    expect(find.text('Merge PDF'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();

    expect(find.text('Tools'), findsWidgets);
    // The framework reports any overflow with the owning widget below.
  });

  testWidgets('missing engine settings link opens the settings page', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DocForgeApp(state: AppState()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Merge PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Open engine settings'), findsOneWidget);

    await tester.tap(find.text('Open engine settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool and settings pages fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: AppState(),
        child: MaterialApp(home: ToolPage(definition: toolRegistry.first)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open engine settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      AppScope(
        state: AppState(),
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Output folder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engine details dialog fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        state: AppState(),
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final details = find.text('Details').first;
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();

    expect(find.text('QPDF engine'), findsOneWidget);
    expect(find.text('Health check'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('option-heavy tool fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final watermark = toolRegistry.firstWhere((tool) => tool.id == 'watermark');
    await tester.pumpWidget(
      AppScope(
        state: AppState(),
        child: MaterialApp(home: ToolPage(definition: watermark)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Watermark'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
