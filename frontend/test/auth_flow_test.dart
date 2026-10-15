import 'dart:convert';
import 'dart:typed_data';

import 'package:cacao/core/api_service.dart';
import 'package:cacao/core/models.dart';
import 'package:cacao/core/pending_uploads.dart';
import 'package:cacao/core/state.dart';
import 'package:cacao/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The payload shape the FastAPI backend returns for `/api/auth/*`.
const Map<String, dynamic> _farmerJson = {
  'id': 1,
  'full_name': 'Rico Respecia',
  'email': 'rico@example.com',
  'role': 'farmer',
};

const Map<String, dynamic> _adminJson = {
  'id': 5,
  'full_name': 'Cacao Admin',
  'email': 'admin@example.com',
  'role': 'admin',
};

/// A row exactly as `GET /api/batches` returns it (PostgreSQL-shaped).
const Map<String, dynamic> _batchJson = {
  'id': 7,
  'user_id': 1,
  'name': 'North Plot Batch',
  'notes': 'Harvested from the north plot.',
  'status': 'Classified',
  'created_at': '2026-10-14T09:00:00',
  'farmer': 'Rico Respecia',
  'record_count': 3,
  'last_classification_at': '2026-10-14T09:05:00',
  'latest_stage': 'well_fermented',
  'latest_confidence': 0.84,
  'latest_filename': 'cut-test-001.jpg',
};

/// A batch that graded badly - the buyer portal flags it for a closer look.
const Map<String, dynamic> _riskyBatchJson = {
  'id': 8,
  'user_id': 1,
  'name': 'South Plot Batch',
  'notes': 'Late harvest.',
  'status': 'Classified',
  'created_at': '2026-10-13T09:00:00',
  'farmer': 'Ashley Cuarenta',
  'record_count': 1,
  'last_classification_at': '2026-10-13T09:05:00',
  'latest_stage': 'over_fermented',
  'latest_confidence': 0.62,
  'latest_filename': 'cut-test-002.jpg',
};

/// The five actors Activity 2, Part A, lists, as `GET /api/roles` returns them.
const List<Map<String, dynamic>> _rolesJson = [
  {'name': 'farmer', 'description': 'Uploads cut-test photos for grading.'},
  {
    'name': 'staff',
    'description': 'Cooperative staff who reviews and standardizes batches.'
  },
  {'name': 'buyer', 'description': 'Checks quality history before purchasing.'},
  {
    'name': 'extension_worker',
    'description': 'Agricultural extension worker monitoring multiple farmer accounts.'
  },
  {'name': 'admin', 'description': 'Manages users and settings.'},
];

const Map<String, dynamic> _buyerJson = {
  'id': 9,
  'full_name': 'Princess Castillo',
  'email': 'princess@example.com',
  'role': 'buyer',
};

const Map<String, dynamic> _workerJson = {
  'id': 10,
  'full_name': 'Extension Worker',
  'email': 'worker@example.com',
  'role': 'extension_worker',
};

const List<String> _roleSlugs = [
  'farmer',
  'staff',
  'buyer',
  'extension_worker',
  'admin',
];

/// Stands in for the FastAPI backend so the widget tests never hit the network.
MockClient buildMockClient({
  Map<String, dynamic>? user,
  bool failLogin = false,
  List<Map<String, dynamic>>? users,
  List<Map<String, dynamic>> batches = const [_batchJson, _riskyBatchJson],

  /// When set, `POST /api/classify` answers with this status instead of
  /// succeeding — used to drive the offline/pending-queue tests from
  /// Activity 2, Part E.
  int? classifyStatus,

  /// Collects one entry per classify attempt, so a test can prove the queue
  /// really did replay the photo.
  List<int>? classifyCalls,
}) {
  return MockClient((request) async {
    const headers = {'content-type': 'application/json'};

    // PATCH /api/admin/users/{id} - role assignment, admins only.
    final roleChange =
        RegExp(r'^/api/admin/users/(\d+)$').firstMatch(request.url.path);
    if (request.method == 'PATCH' && roleChange != null) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final slug = '${body['role'] ?? ''}';
      if (!_roleSlugs.contains(slug)) {
        return http.Response(jsonEncode({'detail': 'Unknown role.'}), 400,
            headers: headers);
      }
      return http.Response(
          jsonEncode({
            'status': 'success',
            'user': {
              'id': int.parse(roleChange.group(1)!),
              'full_name': 'Updated Account',
              'email': 'updated@example.com',
              'role': slug,
            },
          }),
          200,
          headers: headers);
    }

    switch (request.url.path) {
      case '/api/auth/login':
        if (failLogin) {
          return http.Response(
              jsonEncode({'detail': 'Incorrect email or password.'}), 401,
              headers: headers);
        }
        return http.Response(
            jsonEncode({
              'status': 'success',
              'token': 'test-token',
              'user': user ?? _farmerJson,
            }),
            200,
            headers: headers);

      case '/api/auth/register':
        return http.Response(
            jsonEncode({
              'status': 'success',
              'token': 'test-token',
              'user': user ?? _farmerJson,
            }),
            200,
            headers: headers);

      case '/api/auth/logout':
        return http.Response(jsonEncode({'status': 'success'}), 200,
            headers: headers);

      case '/api/admin/users':
        return http.Response(
            jsonEncode({
              'status': 'success',
              'count': (users ?? [_adminJson, _farmerJson]).length,
              'data': users ?? [_adminJson, _farmerJson],
            }),
            200,
            headers: headers);

      // Part D: the backend stores the photo, runs the CNN, writes the
      // quality note/recommendation, and answers with that payload.
      case '/api/classify':
        classifyCalls?.add(request.url.hashCode);
        if (classifyStatus != null) {
          final detail = classifyStatus == 400
              ? 'CNN service could not read the image.'
              : 'CNN service is unavailable.';
          return http.Response(jsonEncode({'detail': detail}), classifyStatus,
              headers: headers);
        }
        return http.Response(
            jsonEncode({
              'status': 'success',
              'id': 42,
              'predicted_class': 'well_fermented',
              'confidence': 0.87,
              'quality_notes': 'Cut surface is an even rich brown.',
              'recommendation': 'Well-fermented cacao bean.',
              'image_url': '/uploads/abc123.jpg',
              'engine': 'heuristic',
            }),
            200,
            headers: headers);

      case '/api/history':
        return http.Response(
            jsonEncode({
              'status': 'success',
              'count': 0,
              'scope': 'own',
              'data': [],
            }),
            200,
            headers: headers);

      case '/api/roles':
        return http.Response(
            jsonEncode({
              'status': 'success',
              'count': _rolesJson.length,
              'data': _rolesJson,
            }),
            200,
            headers: headers);

      case '/api/batches':
        return http.Response(
            jsonEncode({
              'status': 'success',
              'count': batches.length,
              'scope': 'own',
              'data': batches,
            }),
            200,
            headers: headers);

      case '/api/trends':
        return http.Response(
            jsonEncode({
              'status': 'success',
              'scope': 'own',
              'total_records': 3,
              'total_batches': 1,
              'average_confidence': 0.812,
              'stages': [
                {'stage': 'unfermented', 'count': 0, 'average_confidence': 0.0},
                {
                  'stage': 'partially_fermented',
                  'count': 1,
                  'average_confidence': 0.75
                },
                {'stage': 'well_fermented', 'count': 2, 'average_confidence': 0.84},
                {'stage': 'over_fermented', 'count': 0, 'average_confidence': 0.0},
              ],
              'daily': [
                {'day': '2026-10-14', 'count': 3},
              ],
            }),
            200,
            headers: headers);

      default:
        return http.Response(jsonEncode({'detail': 'Not found.'}), 404,
            headers: headers);
    }
  });
}

Future<void> pumpApp(WidgetTester tester,
    {Map<String, String> seedPrefs = const {}}) async {
  SharedPreferences.setMockInitialValues(seedPrefs);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const CacaoGradeApp(),
  ));
  await tester.pumpAndSettle();
}

Future<void> fillAndSubmitLogin(
  WidgetTester tester, {
  String email = 'rico@example.com',
  String password = 'password123',
}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Login'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));

  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);

  await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
  await tester.pumpAndSettle();
}

void main() {
  void useWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  setUp(() {
    CacaoApi.client = buildMockClient();
  });

  testWidgets('farmer login opens the farmer portal', (tester) async {
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester);

    expect(find.text('Farmer Dashboard'), findsOneWidget);
    expect(find.text('Classify Beans'), findsWidgets);
    expect(find.text('Batch History'), findsWidgets);

    // Farmer must not see the admin workspace.
    expect(find.text('User Management'), findsNothing);
  });

  testWidgets('a buyer login opens the read-only buyer portal', (tester) async {
    CacaoApi.client = buildMockClient(user: _buyerJson);
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester, email: 'princess@example.com');

    // Activity 2, Part A: "Buyer (checks quality history)".
    expect(find.text('Buyer Dashboard'), findsOneWidget);
    expect(find.text('Quality History'), findsWidgets);
    expect(find.text('Farmer Directory'), findsWidgets);

    // A buyer never grades cacao, so the upload screen is not offered.
    expect(find.text('Classify Beans'), findsNothing);
    expect(find.text('User Management'), findsNothing);
  });

  testWidgets('the buyer portal flags a batch for a closer look',
      (tester) async {
    CacaoApi.client = buildMockClient(user: _buyerJson);
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester, email: 'princess@example.com');
    await tester.pumpAndSettle();

    expect(find.text('Batches Worth a Closer Look'), findsOneWidget);
    // The over-fermented fixture batch and its grade.
    expect(find.text('South Plot Batch'), findsWidgets);
    expect(find.text('Over-Fermented'), findsWidgets);

    // The supplier is what a buyer actually cares about, and the directory
    // groups lots by the batch's owner.
    await tester.tap(find.text('Farmer Directory').first);
    await tester.pumpAndSettle();

    expect(find.text('Ashley Cuarenta'), findsOneWidget);
    expect(find.text('Rico Respecia'), findsOneWidget);
  });

  testWidgets('an extension worker login opens the multi-account portal',
      (tester) async {
    CacaoApi.client = buildMockClient(user: _workerJson);
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester, email: 'worker@example.com');

    // Activity 2, Part A: "Agricultural extension worker (monitors multiple
    // farmer accounts)".
    expect(find.text('Advisory Dashboard'), findsOneWidget);
    expect(find.text('Farmer Accounts'), findsWidgets);

    // Also read-only, and it must not reach the admin console either.
    expect(find.text('Classify Beans'), findsNothing);
    expect(find.text('User Management'), findsNothing);
  });

  testWidgets('the extension worker overview groups batches by account',
      (tester) async {
    CacaoApi.client = buildMockClient(user: _workerJson);
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester, email: 'worker@example.com');
    await tester.pumpAndSettle();

    expect(find.text('Accounts With No Cut Test Yet'), findsOneWidget);

    // Two distinct suppliers appear across the two fixture batches, and the
    // account view rolls each one up on its own card.
    await tester.tap(find.text('Farmer Accounts').first);
    await tester.pumpAndSettle();

    expect(find.text('Ashley Cuarenta'), findsOneWidget);
    expect(find.text('Rico Respecia'), findsOneWidget);
    expect(find.text('Grading coverage'), findsWidgets);
  });

  testWidgets('a phone-width portal routes through the bottom navigation',
      (tester) async {
    // The landing page has its own phone layout, which is not what is under
    // test here, so sign in wide and then shrink the window. The shell reads
    // the width in build(), so it swaps the sidebar for the bottom bar.
    useWideScreen(tester);
    await pumpApp(tester);
    await fillAndSubmitLogin(tester);

    tester.view.physicalSize = const Size(430, 900);
    await tester.pumpAndSettle();

    // Activity 2, Part A - "bottom navigation and role-based routing".
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));

    // The sidebar is gone at this width; its entries moved into the bar.
    expect(find.text('Back to Home'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Classify Beans'), findsOneWidget);
    expect(find.text('Batch History'), findsOneWidget);
    expect(find.text('My Profile'), findsOneWidget);

    // A role never gains or loses a destination by rotating the device.
    expect(find.text('User Management'), findsNothing);

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.photo_camera_outlined)));
    await tester.pumpAndSettle();

    // The title appears in the top bar and again as the page heading.
    expect(find.text('Classify Cacao Beans'), findsWidgets);
  });

  testWidgets('the bottom bar switches screens and tracks the selection',
      (tester) async {
    useWideScreen(tester);
    await pumpApp(tester);
    await fillAndSubmitLogin(tester);

    tester.view.physicalSize = const Size(430, 900);
    await tester.pumpAndSettle();

    // The dashboard is the landing screen inside the portal.
    expect(find.text('CACAO QUALITY MANAGEMENT'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.inventory_2_outlined)));
    await tester.pumpAndSettle();

    // Batch History carries its own heading rather than the greeting.
    expect(find.text('CACAO QUALITY MANAGEMENT'), findsNothing);

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.person_outline)));
    await tester.pumpAndSettle();

    expect(find.text('My Profile'), findsWidgets);
  });

  testWidgets('the admin portal still fits six destinations on a phone',
      (tester) async {
    CacaoApi.client = buildMockClient(user: _adminJson);
    useWideScreen(tester);
    await pumpApp(tester);
    await fillAndSubmitLogin(tester, email: 'admin@example.com');

    tester.view.physicalSize = const Size(430, 900);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(6));

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.group_outlined)));
    await tester.pumpAndSettle();

    expect(find.text('User Management'), findsWidgets);
  });

  // Activity 2, Part E names network dependency as the main risk and asks that
  // uploads be "queued or clearly flagged as pending rather than silently
  // lost"; the reflection adds "automatically retry ... once connectivity is
  // restored". These cover that contract.

  /// Stands in for a relaunched app sharing the same local storage.
  ///
  /// A token is seeded because `CacaoApi.classify` refuses without a session,
  /// exactly as the backend would (Part D, step 4).
  Future<ProviderContainer> makeContainer(
      {Map<String, Object> seed = const {}}) async {
    SharedPreferences.setMockInitialValues(
        {'cacao_auth_token': 'test-token', ...seed});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  PendingUpload queuedPhoto() => PendingUpload(
        id: '1',
        batchName: 'Queued Batch',
        notes: '',
        fileName: 'cut-test.jpg',
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        queuedAt: DateTime.now(),
      );

  test('a photo the classifier cannot reach is queued, not lost', () async {
    CacaoApi.client = buildMockClient(classifyStatus: 503);
    final container = await makeContainer();
    final notifier = container.read(pendingUploadsProvider.notifier);

    await notifier.enqueue(
      imageBytes: queuedPhoto().imageBytes,
      fileName: 'cut-test.jpg',
      batchName: 'Queued Batch',
      notes: '',
      reason: 'CNN service is unavailable.',
    );

    final queue = container.read(pendingUploadsProvider);
    expect(queue, hasLength(1));
    expect(queue.single.batchName, 'Queued Batch');
    expect(queue.single.lastError, contains('unavailable'));
    expect(queue.single.permanent, isFalse);

    // Still down: the photo stays put and the attempt is recorded.
    expect(await notifier.flush(), 0);
    expect(container.read(pendingUploadsProvider), hasLength(1));
    expect(container.read(pendingUploadsProvider).single.attempts, 1);
  });

  test('the queue replays a photo once the service answers again', () async {
    final calls = <int>[];
    CacaoApi.client =
        buildMockClient(classifyStatus: 503, classifyCalls: calls);
    final container = await makeContainer();
    final notifier = container.read(pendingUploadsProvider.notifier);

    await notifier.enqueue(
      imageBytes: queuedPhoto().imageBytes,
      fileName: 'cut-test.jpg',
      batchName: 'Queued Batch',
      notes: 'Harvested from the north plot.',
    );
    expect(await notifier.flush(), 0);
    expect(calls, hasLength(1));

    // Connectivity returns.
    CacaoApi.client = buildMockClient(classifyCalls: calls);

    expect(await notifier.flush(), 1);
    expect(container.read(pendingUploadsProvider), isEmpty);
    expect(calls, hasLength(2));
  });

  test('a photo the classifier cannot read is rejected, not replayed',
      () async {
    CacaoApi.client = buildMockClient(classifyStatus: 400);
    final container = await makeContainer();
    final notifier = container.read(pendingUploadsProvider.notifier);

    await notifier.enqueue(
      imageBytes: queuedPhoto().imageBytes,
      fileName: 'cut-test.jpg',
      batchName: 'Unreadable Batch',
      notes: '',
      reason: 'CNN service could not read the image.',
    );
    await notifier.flush();

    final queue = container.read(pendingUploadsProvider);
    expect(queue, hasLength(1));
    expect(queue.single.permanent, isTrue);
    expect(queue.single.lastError, contains('could not read'));

    // Flushing again leaves it alone rather than spinning on a photo that
    // would fail identically forever.
    expect(await notifier.flush(), 0);
    expect(container.read(pendingUploadsProvider), hasLength(1));
  });

  test('the queue is still there after the app restarts', () async {
    CacaoApi.client = buildMockClient(classifyStatus: 503);

    SharedPreferences.setMockInitialValues({});
    final first = await SharedPreferences.getInstance();
    final before = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(first)],
    );
    addTearDown(before.dispose);

    await before.read(pendingUploadsProvider.notifier).enqueue(
          imageBytes: Uint8List.fromList([9, 9, 9]),
          fileName: 'cut-test.jpg',
          batchName: 'Survives Restart',
          notes: 'Left queued overnight.',
        );

    final stored = first.getString('pending_uploads');
    expect(stored, isNotNull, reason: 'the queue has to reach local storage');

    final after = await makeContainer(seed: {'pending_uploads': stored!});
    await after.read(pendingUploadsProvider.notifier).ready();

    final queue = after.read(pendingUploadsProvider);
    expect(queue.single.batchName, 'Survives Restart');
    expect(queue.single.notes, 'Left queued overnight.');
    expect(queue.single.imageBytes, [9, 9, 9]);
  });

  testWidgets('the upload screen shows a pending photo instead of losing it',
      (tester) async {
    CacaoApi.client = buildMockClient(classifyStatus: 503);
    useWideScreen(tester);
    await pumpApp(tester);
    await fillAndSubmitLogin(tester);

    await tester.tap(find.text('Classify Beans').first);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)));
    // A real 1x1 PNG, since the panel renders the queued photo's thumbnail.
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
        'DwAChwGA60e6kgAAAABJRU5ErkJggg==');
    await container.read(pendingUploadsProvider.notifier).enqueue(
          imageBytes: png,
          fileName: 'cut-test.png',
          batchName: 'Queued While Offline',
          notes: '',
          reason: 'CNN service is unavailable.',
        );
    await tester.pumpAndSettle();

    // "show a clear offline/pending status to the user".
    expect(find.text('Pending Uploads'), findsOneWidget);
    expect(find.text('Queued While Offline'), findsOneWidget);
    expect(find.textContaining('waiting for the classifier'), findsOneWidget);
    expect(find.text('Retry now'), findsOneWidget);

    // The farmer keeps the last word - nothing is dropped automatically.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  test('roleLabel maps every slug the document uses onto its actor',
      () {
    expect(roleLabel('farmer'), 'Farmer');
    expect(roleLabel('cooperative_staff'), 'Staff');
    expect(roleLabel('Cooperative Staff'), 'Staff');
    expect(roleLabel('buyer'), 'Buyer');
    expect(roleLabel('agricultural_extension_worker'), 'Extension Worker');
    expect(roleLabel('Extension Worker'), 'Extension Worker');
    expect(roleLabel('administrator'), 'Admin');
    expect(roleLabel('anything-else'), 'Farmer');

    expect(kRoleLabels, hasLength(5));
    expect(kRoleLabels, containsAll(['Buyer', 'Extension Worker']));
  });

  test('roleSlug round-trips every label back to its backend slug', () {
    expect(roleSlug('Farmer'), 'farmer');
    expect(roleSlug('Staff'), 'staff');
    expect(roleSlug('Buyer'), 'buyer');
    expect(roleSlug('Extension Worker'), 'extension_worker');
    expect(roleSlug('Admin'), 'admin');
  });

  test('updateUserRole PATCHes the backend with the role slug', () async {
    CacaoApi.client = buildMockClient();

    final body = await CacaoApi.updateUserRole(6, roleSlug('Extension Worker'));

    expect((body['user'] as Map)['role'], 'extension_worker');
  });

  testWidgets('the farmer dashboard reads batches and trends from the server',
      (tester) async {
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester);
    await tester.pumpAndSettle();

    // From GET /api/batches.
    expect(find.text('North Plot Batch'), findsWidgets);

    // From GET /api/trends.
    expect(find.text('Fermentation Trends'), findsOneWidget);
    expect(find.text('Well-Fermented'), findsWidgets);
    expect(find.text('2 records · 84% avg'), findsOneWidget);
    expect(find.text('81.2%'), findsOneWidget);
  });

  testWidgets('admin login opens the admin portal with backend users',
      (tester) async {
    useWideScreen(tester);
    CacaoApi.client = buildMockClient(user: _adminJson);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester);

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.text('User Management'), findsWidgets);
    expect(find.text('Classifications'), findsWidgets);
    expect(find.text('Classify Beans'), findsNothing);

    // Open User Management - the list must come from GET /api/admin/users.
    await tester.tap(find.text('User Management').first);
    await tester.pumpAndSettle();

    expect(find.text('Cacao Admin'), findsWidgets);
    expect(find.text('Rico Respecia'), findsWidgets);
  });

  testWidgets('wrong password shows the backend error and stays signed out',
      (tester) async {
    useWideScreen(tester);
    CacaoApi.client = buildMockClient(failLogin: true);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester, password: 'nope');

    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.text('Farmer Dashboard'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('register creates the account and opens its portal',
      (tester) async {
    useWideScreen(tester);
    CacaoApi.client = buildMockClient(user: _farmerJson);
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));
    await tester.enterText(fields.at(0), 'Rico Respecia');
    await tester.enterText(fields.at(1), 'rico@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('Farmer Dashboard'), findsOneWidget);
  });

  testWidgets('a stored session goes straight to its dashboard',
      (tester) async {
    useWideScreen(tester);
    await pumpApp(tester, seedPrefs: {
      'ACC_auth_user': jsonEncode({
        'id': '1',
        'name': 'Rico Respecia',
        'email': 'rico@example.com',
        'role': 'Farmer',
        'status': 'Active',
      }),
      'cacao_auth_token': 'stored-token',
    });

    expect(find.text('Farmer Dashboard'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Login'), findsNothing);
  });

  testWidgets('log out returns to the landing page', (tester) async {
    useWideScreen(tester);
    await pumpApp(tester);

    await fillAndSubmitLogin(tester);
    expect(find.text('Farmer Dashboard'), findsOneWidget);

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Farmer Dashboard'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });
}
