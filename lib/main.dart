import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'core/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  final state = AppState();
  await state.initialize();

  runApp(DocForgeApp(state: state));
}
