# CacaoGrade AI — Flutter App

The **client** of **CacaoGrade AI** (IT 110 Activity 2). Talks to the FastAPI backend in
`../backend/` over HTTP.

This is the only client now — the old HTML/CSS/JS web app has been removed.

## Layout

```
lib/
├── core/
│   ├── api_service.dart     # HTTP client (CacaoApi) + token storage
│   ├── state.dart           # Riverpod providers: auth, users, batches, activity
│   ├── pending_uploads.dart # offline queue: photos the classifier could not take
│   ├── dashboard_shell.dart # shared sidebar + bottom navigation + topbar
│   ├── theme.dart           # dark/light theme
│   ├── widgets.dart         # shared UI pieces
│   └── models.dart          # Batch, AppUser, roleLabel/roleSlug/stageName
└── screens/
    ├── landing_page.dart    # landing + login/register dialog + role-based routing
    ├── farmer_dashboard.dart              # upload / classify, history, profile
    ├── staff_dashboard.dart               # batch management + classification review
    ├── buyer_dashboard.dart               # read-only quality history
    ├── extension_worker_dashboard.dart    # read-only, per-farmer monitoring
    └── admin_dashboard.dart               # user management + system monitoring

assets/images/               # bundled images (logo, hero, bean stages)
test/                        # widget, auth-flow, and classify API tests (27)
```

Each portal is picked by `buildPortal()` in `landing_page.dart` from the role the
backend returns, and the backend enforces the same split: a `buyer` or
`extension_worker` session gets 403 on `POST /api/classify` and on deleting a batch it
does not own, while `GET /api/batches`, `GET /api/history` and `GET /api/trends` return
every account rather than only the caller's.

`DashboardShell` shows a sidebar at 960px and above, and a Material `NavigationBar`
below it, so the app keeps the *"bottom navigation and role-based routing"* the
document asks for on a phone.

### When the backend is unreachable

`core/pending_uploads.dart` keeps a cut-test photo the classifier could not take,
writes it to `SharedPreferences`, shows it in the **Pending Uploads** panel on the
farmer's Classify screen, and replays it every 20 seconds. Discarding is always the
farmer's decision — Activity 2, Part E rules out silently losing the photo.

## Run

```bash
flutter pub get
flutter run -d chrome
```

`flutter analyze` and `flutter test` are the quality gates (0 errors / 0 warnings; 27 tests).

## Backend URL

`kApiBaseUrl` in `lib/core/api_service.dart`:

- Web / desktop → `http://127.0.0.1:8000` (default)
- Android emulator → `http://10.0.2.2:8000`
- Real device → your PC's LAN IP, e.g. `http://192.168.1.10:8000`

## Version pins

- `google_fonts: ^8.0.0` — 9.x pulls a `material_ui` package whose `TextTheme` is a
  different class from Flutter's, which breaks `core/theme.dart`.
- `file_picker: 10.3.7` — 13.x removed `FilePicker.platform`.
