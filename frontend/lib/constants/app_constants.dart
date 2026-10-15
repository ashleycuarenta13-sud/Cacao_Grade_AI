/// App-wide values that would otherwise be spelled out in more than one place.
library;
///
///
/// Nothing here is a secret: every entry is either a default a fresh checkout
/// runs on, or a bound both halves of the stack have to agree on.

/// Base URL of the CacaoGrade AI FastAPI backend.
///
/// - Windows / macOS / Linux / iOS simulator -> http://127.0.0.1:8000
/// - Android emulator                         -> http://10.0.2.2:8000
/// - Real phone                               -> `http://<your-PC-LAN-IP>:8000`
///
/// Override it without editing this file by passing a `--dart-define`, which is
/// how the HTTPS setup switches schemes:
///
/// ```bash
/// flutter run -d chrome --dart-define=CACAO_API=https://127.0.0.1:8000
/// ```
///
/// The HTTPS setup uses the self-signed certificate from `backend/make_cert.py`,
/// so the browser will warn you once on localhost. Accept it for localhost, and
/// use a real certificate for anything public.
const String kApiBaseUrl = String.fromEnvironment(
  'CACAO_API',
  defaultValue: 'http://127.0.0.1:8000',
);

/// The bound Activity 3, Part C states for the upload screen:
/// *"File type (jpg/png) and size (<10MB) check"*.
///
/// Kept identical to `MAX_IMAGE_BYTES` in the API so the two halves can never
/// disagree about what is acceptable - the client check exists only so a farmer
/// is told immediately rather than after a round-trip.
const int kMaxImageBytes = 10 * 1024 * 1024;

/// What Part C allows through.
const List<String> kAllowedImageExtensions = ['jpg', 'jpeg', 'png'];

/// How often the offline queue replays itself.
///
/// Short enough that a farmer who left the tab open notices the recovery
/// quickly, long enough that an unreachable backend is not hammered while it
/// is down.
const Duration kPendingRetryInterval = Duration(seconds: 20);
