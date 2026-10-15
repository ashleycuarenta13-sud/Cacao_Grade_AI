import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'models.dart';

const _kTheme = 'ACC_theme';
const _kBatches = 'ACC_farmer_batches';
const _kUsers = 'ACC_registered_users';
const _kActivity = 'ACC_admin_activity';

/// Overridden in main() after SharedPreferences is ready.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

List<Map<String, dynamic>> _readList(SharedPreferences p, String key) {
  try {
    final s = p.getString(key);
    if (s == null) return [];
    final d = jsonDecode(s);
    if (d is List) {
      return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
  } catch (_) {}
  return [];
}

// ---------- Theme ----------
class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ref.read(prefsProvider).getString(_kTheme) == 'dark' ? ThemeMode.dark : ThemeMode.light;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    ref.read(prefsProvider).setString(_kTheme, state == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);

// ---------- Batches ----------
class BatchesNotifier extends Notifier<List<Batch>> {
  @override
  List<Batch> build() => _readList(ref.read(prefsProvider), _kBatches).map(Batch.fromJson).toList();

  void _save() => ref
      .read(prefsProvider)
      .setString(_kBatches, jsonEncode(state.map((b) => b.toJson()).toList()));

  void add(Batch b) {
    state = [b, ...state];
    _save();
  }

  void clear() {
    state = [];
    _save();
  }
}

final batchesProvider = NotifierProvider<BatchesNotifier, List<Batch>>(BatchesNotifier.new);

/// Batch records as stored on the server (`GET /api/batches`).
///
/// Replaces the device-local [batchesProvider] for anything the user reads
/// back: the backend scopes farmers to their own batches and lets staff and
/// admins see every one.
final serverBatchesProvider = FutureProvider<List<Batch>>((ref) async {
  final rows = await CacaoApi.fetchBatches();
  return rows.map(Batch.fromApi).toList();
});

/// Dashboard aggregation computed by the backend (`GET /api/trends`): stage
/// counts, average confidence, and the daily series.
final trendsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return CacaoApi.fetchTrends();
});

/// Reloads [usersProvider] from `GET /api/admin/users` (admins only).
///
/// Shared by the landing page's post-login load and by the admin console
/// after it assigns a role, so both paths refresh the same store.
Future<void> refreshUsers(WidgetRef ref) async {
  final rows = await CacaoApi.fetchUsers();
  ref.read(usersProvider.notifier)
      .replaceAll(rows.map(CacaoApi.userFromApi).toList());
}

// ---------- Users ----------
class UsersNotifier extends Notifier<List<AppUser>> {
  @override
  List<AppUser> build() => _readList(ref.read(prefsProvider), _kUsers).map(AppUser.fromJson).toList();

  void add(AppUser u) {
    state = [u, ...state];
    ref.read(prefsProvider).setString(_kUsers, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  AppUser? findByEmail(String email) {
    for (final u in state) {
      if (u.email.toLowerCase() == email.trim().toLowerCase()) return u;
    }
    return null;
  }

  /// Overwrites the local list with the accounts returned by the backend.
  void replaceAll(List<AppUser> list) {
    state = list;
    ref.read(prefsProvider).setString(_kUsers, jsonEncode(state.map((e) => e.toJson()).toList()));
  }
}

final usersProvider = NotifierProvider<UsersNotifier, List<AppUser>>(UsersNotifier.new);

// ---------- Signed-in session ----------
const _kAuthUser = 'ACC_auth_user';

/// The account that is currently logged in, restored from [SharedPreferences]
/// on app start so the session survives a restart.
class AuthNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() {
    final prefs = ref.read(prefsProvider);
    final raw = prefs.getString(_kAuthUser);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void signIn(AppUser user) {
    state = user;
    ref.read(prefsProvider).setString(_kAuthUser, jsonEncode(user.toJson()));
  }

  void signOut() {
    state = null;
    ref.read(prefsProvider).remove(_kAuthUser);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);

// ---------- Activity log ----------
class ActivityNotifier extends Notifier<List<ActivityItem>> {
  @override
  List<ActivityItem> build() =>
      _readList(ref.read(prefsProvider), _kActivity).map(ActivityItem.fromJson).toList();

  void _save() => ref
      .read(prefsProvider)
      .setString(_kActivity, jsonEncode(state.map((e) => e.toJson()).toList()));

  void log(String action, String details) {
    state = [ActivityItem(action: action, details: details, time: DateTime.now()), ...state];
    _save();
  }

  void clear() {
    state = [];
    _save();
  }
}

final activityProvider = NotifierProvider<ActivityNotifier, List<ActivityItem>>(ActivityNotifier.new);
