class Batch {
  final String id;
  final String name;
  final String notes;
  final String fileName;
  final String status; // Pending | Classified | Verified | Flagged
  final String? stage;
  final double? confidence; // 0.0 - 1.0
  final String? qualityNotes;
  final String? recommendation;
  final DateTime createdAt;

  /// The farmer who submitted the batch, and how many classification records
  /// it holds. Both come from `GET /api/batches`; they let the buyer and
  /// extension-worker portals group batches without a second round-trip.
  final String farmer;
  final int recordCount;

  const Batch({
    required this.id,
    required this.name,
    this.notes = '',
    this.fileName = '',
    this.status = 'Pending',
    this.stage,
    this.confidence,
    this.qualityNotes,
    this.recommendation,
    required this.createdAt,
    this.farmer = '',
    this.recordCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'fileName': fileName,
        'status': status,
        'stage': stage,
        'confidence': confidence,
        'qualityNotes': qualityNotes,
        'recommendation': recommendation,
        'createdAt': createdAt.toIso8601String(),
        'farmer': farmer,
        'recordCount': recordCount,
      };

  factory Batch.fromJson(Map<String, dynamic> j) => Batch(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Unnamed Batch'}',
        notes: '${j['notes'] ?? ''}',
        fileName: '${j['fileName'] ?? ''}',
        status: '${j['status'] ?? 'Pending'}',
        stage: j['stage'] is String ? j['stage'] as String : null,
        confidence: j['confidence'] is num ? (j['confidence'] as num).toDouble() : null,
        qualityNotes: j['qualityNotes'] as String?,
        recommendation: j['recommendation'] as String?,
        createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
        farmer: '${j['farmer'] ?? ''}',
        recordCount: j['recordCount'] is num ? (j['recordCount'] as num).toInt() : 0,
      );

  String get stageLabel => stage == null ? 'Awaiting classification' : stageName(stage!);
  String get confidenceLabel =>
      confidence == null ? 'Unavailable' : '${(confidence! * 100).toStringAsFixed(1)}%';

  /// Maps a row returned by the backend's `GET /api/batches`.
  ///
  /// The server answers with `farmer`, `record_count`, and the batch's latest
  /// classification rather than with the local `fileName`/`stage` spelling.
  factory Batch.fromApi(Map<String, dynamic> j) => Batch(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Unnamed Batch'}',
        notes: '${j['notes'] ?? ''}',
        fileName: '${j['latest_filename'] ?? ''}',
        status: '${j['status'] ?? 'Pending'}',
        stage: j['latest_stage'] is String ? j['latest_stage'] as String : null,
        confidence: j['latest_confidence'] is num
            ? (j['latest_confidence'] as num).toDouble()
            : null,
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
        farmer: '${j['farmer'] ?? ''}',
        recordCount: j['record_count'] is num ? (j['record_count'] as num).toInt() : 0,
      );
}

/// `'well_fermented'` -> `'Well-Fermented'`.
///
/// Lives here rather than in widgets.dart so the models can label a stage
/// without pulling in the widget tree.
String stageName(String raw) {
  final words = raw.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  if (words.isEmpty) return 'Unknown stage';
  return words
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join('-');
}

/// The five actors Activity 2, Part A, lists, in the document's order.
const List<String> kRoleLabels = [
  'Farmer',
  'Staff',
  'Buyer',
  'Extension Worker',
  'Admin',
];

/// Maps a backend role slug - or the document's actor name - onto the label
/// the UI shows. `'extension_worker'` -> `'Extension Worker'`.
String roleLabel(String raw) {
  final key = raw.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
  switch (key) {
    case 'staff':
    case 'cooperative_staff':
    case 'coop_staff':
    case 'co_op_staff':
      return 'Staff';
    case 'buyer':
    case 'cacao_buyer':
      return 'Buyer';
    case 'extension_worker':
    case 'agricultural_extension_worker':
    case 'extensionist':
      return 'Extension Worker';
    case 'admin':
    case 'administrator':
      return 'Admin';
    default:
      return 'Farmer';
  }
}

/// The reverse of [roleLabel]: `'Extension Worker'` -> `'extension_worker'`,
/// which is the slug `users.role` stores.
String roleSlug(String label) =>
    roleLabel(label).toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

class AppUser {
  final String id;
  final String name;
  final String email;

  /// One of the five documented actors, as the UI labels it:
  /// `Farmer | Staff | Buyer | Extension Worker | Admin`.
  final String role;
  final String status;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.role = 'Farmer',
    this.status = 'Active',
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'email': email, 'role': role, 'status': status};

  /// The slug the backend stores in `users.role`, e.g. `extension_worker`.
  String get roleKey => roleSlug(role);

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Unnamed User'}',
        email: '${j['email'] ?? ''}',
        role: roleLabel('${j['role'] ?? 'Farmer'}'),
        status: '${j['status'] ?? 'Active'}',
      );
}

class ActivityItem {
  final String action;
  final String details;
  final DateTime time;
  const ActivityItem({required this.action, required this.details, required this.time});

  Map<String, dynamic> toJson() =>
      {'action': action, 'details': details, 'time': time.toIso8601String()};

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        action: '${j['action'] ?? ''}',
        details: '${j['details'] ?? ''}',
        time: DateTime.tryParse('${j['time']}') ?? DateTime.now(),
      );
}
