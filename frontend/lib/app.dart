import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cacao/providers/state.dart';
import 'package:cacao/screens/landing/landing_page.dart';
import 'package:cacao/theme.dart';

/// The widget tree of CacaoGrade AI.
///
/// Activity 8, Screenshot 2 lists `app.dart` as part of the required `lib/`
/// source tree. Keeping it apart from `main.dart` is what lets a widget test
/// pump the whole application without first doing the asynchronous work
/// `main()` is responsible for - `test/widget_test.dart` does exactly that.
///
/// The layout: a Riverpod `ProviderScope` sits above the tree (built in
/// `main()`), the theme is chosen by `themeProvider`, and `LandingPage` is the
/// home because every session - signed in or not - starts there.
class CacaoGradeApp extends ConsumerWidget {
  const CacaoGradeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'CacaoGrade AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: const LandingPage(),
    );
  }
}
