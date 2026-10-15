import 'package:flutter/material.dart';

/// Route names and the route builder the application pushes with.
///
/// Activity 8, Screenshot 2 lists `routes/` as part of the required `lib/`
/// source tree.
///
/// CacaoGrade AI's screens are switched in place by the bottom navigation bar
/// (`widgets/dashboard_shell.dart`), so most navigation never leaves a single
/// page. The exception is a signed-in session leaving the landing page for its
/// role portal - that *does* push a new route, and it goes through
/// [AppRoutes.page] so every push in the app is built the same way.
///
/// The names below are also what a route table would key off, which is why they
/// are declared even though the portal screens are currently reached by
/// building them directly.
class AppRoutes {
  const AppRoutes._();

  /// The landing page, and therefore the route the app opens on.
  static const String landing = '/';

  /// The signed-in area behind a session: farmer, staff, admin, buyer or
  /// extension worker, chosen by the account's role.
  static const String portal = '/portal';

  /// Builds the route used to move from the landing page to a portal.
  ///
  /// A single [MaterialPageRoute] so the platform-appropriate transition is
  /// picked by Flutter rather than being spelled out at each call site.
  static Route<T> page<T>(Widget screen) =>
      MaterialPageRoute<T>(builder: (_) => screen);
}
