import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cacao/app.dart';
import 'package:cacao/providers/state.dart';

/// Entry point: asynchronous setup only, then hand over to [CacaoGradeApp].
///
/// Activity 8, Screenshot 2 expects `main.dart` to be the bootstrap of an
/// organised `lib/` tree. Everything that decides how the application *looks*
/// lives in `app.dart`; everything that has to happen before the first frame -
/// loading the persisted preferences that Riverpod's [prefsProvider] exposes -
/// lives here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const CacaoGradeApp(),
    ),
  );
}
