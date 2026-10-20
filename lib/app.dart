import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'features/history/history_page.dart';
import 'features/home/home_page.dart';
import 'features/settings/settings_page.dart';
import 'features/viewer/viewer_page.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class DocForgeApp extends StatelessWidget {
  const DocForgeApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'DocForge',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: state.settings.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.grid_view_rounded, selected: Icons.grid_view_rounded, label: 'Tools'),
    (icon: Icons.picture_as_pdf_outlined, selected: Icons.picture_as_pdf_rounded, label: 'Viewer'),
    (icon: Icons.history_rounded, selected: Icons.history_rounded, label: 'History'),
    (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = [
      HomePage(onOpenViewer: () => setState(() => _index = 1)),
      const ViewerPage(embedded: true),
      const HistoryPage(embedded: true),
      const SettingsPage(embedded: true),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final content = IndexedStack(index: _index, children: pages);

        if (wide) {
          return Scaffold(
            backgroundColor: scheme.surface,
            body: Row(
              children: [
                NavigationRail(
                  extended: constraints.maxWidth >= 1180,
                  selectedIndex: _index,
                  onDestinationSelected: (index) => setState(() => _index = index),
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: AppMark(size: 36),
                  ),
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selected),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: scheme.surface,
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: [
              for (final destination in _destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selected),
                  label: destination.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
