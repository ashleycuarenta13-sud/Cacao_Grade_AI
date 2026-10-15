/// Offline / pending upload queue.
///
/// Activity 2, Part E names network dependency as the architecture's main
/// risk, and asks for this exact behaviour:
///
///   > *"if the inference service or connectivity is unavailable, uploads must
///   > be queued or clearly flagged as pending rather than silently lost."*
///
/// and, in the post-laboratory reflection:
///
///   > *"The Flutter client should detect the failure, cache the pending
///   > photo/upload locally, show a clear offline/pending status to the user,
///   > and automatically retry submission once connectivity is restored,
///   > rather than silently failing or losing the farmer's photo."*
///
/// So: a photo that cannot be classified right now is remembered instead of
/// discarded, the farmer can see that it is waiting, and it is replayed on a
/// timer without anybody having to do anything.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_service.dart';
import 'state.dart';

/// How often the queue replays itself.
///
/// Short enough that a farmer who left the tab open notices the recovery
/// quickly, long enough that an unreachable backend is not hammered while it
/// is down.
const Duration kPendingRetryInterval = Duration(seconds: 20);

const String _storageKey = 'pending_uploads';

/// One cut-test photo waiting to be classified.
@immutable
class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.batchName,
    required this.notes,
    required this.fileName,
    required this.imageBytes,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
    this.permanent = false,
    this.persisted = true,
  });

  final String id;
  final String batchName;
  final String notes;
  final String fileName;
  final Uint8List imageBytes;
  final DateTime queuedAt;

  /// How many times this photo has been replayed. Shown to the farmer so a
  /// stuck item does not look like it is being ignored.
  final int attempts;

  final String? lastError;

  /// True when retrying can never help — a photo the CNN could not read, or a
  /// session that has been signed out. The photo is still kept (never silently
  /// lost), but it is marked as rejected so the farmer can act on it.
  final bool permanent;

  /// False when the browser or device refused to store the queue, so this item
  /// survives only for the current session. Surfaced rather than hidden.
  final bool persisted;

  PendingUpload copyWith({
    int? attempts,
    String? lastError,
    bool? permanent,
    bool? persisted,
  }) {
    return PendingUpload(
      id: id,
      batchName: batchName,
      notes: notes,
      fileName: fileName,
      imageBytes: imageBytes,
      queuedAt: queuedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      permanent: permanent ?? this.permanent,
      persisted: persisted ?? this.persisted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'batch_name': batchName,
        'notes': notes,
        'file_name': fileName,
        'image': base64Encode(imageBytes),
        'queued_at': queuedAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'permanent': permanent,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> json) {
    return PendingUpload(
      id: '${json['id']}',
      batchName: '${json['batch_name'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      fileName: '${json['file_name'] ?? 'cut-test.jpg'}',
      imageBytes: base64Decode('${json['image'] ?? ''}'),
      queuedAt: DateTime.tryParse('${json['queued_at']}') ?? DateTime.now(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
      permanent: json['permanent'] == true,
    );
  }
}

/// True when the failure is one a retry could plausibly fix.
///
/// A null status code means the request never reached the server at all — a
/// dropped connection, a laptop that slept, a backend mid-restart. 502/503/504
/// mean the API answered but the inference hop behind it did not. Everything
/// else — an unreadable photo, a rejected role, an expired session — would
/// fail identically forever, so replaying it would only spin.
bool isRetryable(ApiException error) {
  final status = error.statusCode;
  return status == null || status == 502 || status == 503 || status == 504;
}

class PendingUploadsNotifier extends Notifier<List<PendingUpload>> {
  bool _flushing = false;
  Future<void>? _ready;

  @override
  List<PendingUpload> build() {
    _ready = _restore();

    // "automatically retry submission once connectivity is restored" — a timer
    // is what makes that happen without the farmer having to notice and press
    // anything.
    final timer = Timer.periodic(kPendingRetryInterval, (_) {
      if (ref.mounted) unawaited(flush());
    });
    ref.onDispose(timer.cancel);

    return const [];
  }

  /// Awaits the one-off read of anything already queued from a last session.
  Future<void> ready() async {
    await _ready;
  }

  Future<void> _restore() async {
    // `state` cannot be written until build() has returned, so yield before
    // touching it. Otherwise the assignment below would run inside build(),
    // be rejected, and be swallowed by the handler meant for bad JSON.
    await Future<void>.delayed(Duration.zero);

    final prefs = ref.read(prefsProvider);
    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final restored = <PendingUpload>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          restored
              .add(PendingUpload.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // One unreadable entry must not stop the rest from coming back.
        }
      }

      if (!ref.mounted || restored.isEmpty) return;
      state = restored;
    } catch (_) {
      // A corrupt queue must not stop the app from starting.
      await prefs.remove(_storageKey);
    }
  }

  Future<void> _persist() async {
    final prefs = ref.read(prefsProvider);

    if (state.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }

    try {
      await prefs.setString(
        _storageKey,
        jsonEncode([for (final item in state) item.toJson()]),
      );

      if (state.any((item) => !item.persisted)) {
        state = [for (final item in state) item.copyWith(persisted: true)];
      }
    } catch (error) {
      // Most likely a storage quota — a base64 photo is large. The queue is
      // kept in memory for this session regardless, which still beats losing
      // the farmer's photo; the flag tells the UI so it can say so plainly.
      debugPrint('Could not persist the pending-upload queue: $error');
      state = [for (final item in state) item.copyWith(persisted: false)];
    }
  }

  /// Adds a photo the backend could not take right now.
  Future<void> enqueue({
    required Uint8List imageBytes,
    required String fileName,
    required String batchName,
    required String notes,
    String? reason,
  }) async {
    await ready();

    state = [
      PendingUpload(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        batchName: batchName,
        notes: notes,
        fileName: fileName,
        imageBytes: imageBytes,
        queuedAt: DateTime.now(),
        lastError: reason,
      ),
      ...state,
    ];

    await _persist();
  }

  /// Replays everything that can still succeed, and reports how many landed.
  ///
  /// Returns the number submitted so the caller can refresh its history —
  /// the queued photo became a real record on the server.
  Future<int> flush() async {
    await ready();

    if (_flushing || state.isEmpty) return 0;

    _flushing = true;
    try {
      var submitted = 0;
      var changed = false;
      final remaining = <PendingUpload>[];

      for (final item in List.of(state)) {
        if (item.permanent) {
          remaining.add(item);
          continue;
        }

        try {
          await CacaoApi.classify(
            bytes: item.imageBytes,
            fileName: item.fileName,
            batchName: item.batchName,
            notes: item.notes,
          );
          submitted += 1;
          changed = true;
        } on ApiException catch (error) {
          // Written back even when every item fails, so the attempt counter
          // and the reason the farmer sees keep moving instead of freezing at
          // their first value.
          remaining.add(item.copyWith(
            attempts: item.attempts + 1,
            lastError: error.message,
            permanent: !isRetryable(error),
          ));
          changed = true;
        }
      }

      if (changed) {
        // The container may have been disposed while the last request was in
        // flight; writing state then would throw for no benefit.
        if (!ref.mounted) return submitted;
        state = remaining;
        await _persist();
      }

      return submitted;
    } finally {
      _flushing = false;
    }
  }

  /// Gives up on one item on the farmer's instruction.
  ///
  /// Explicit, never automatic — the whole point of the queue is that nothing
  /// disappears without the farmer deciding it should.
  Future<void> discard(String id) async {
    await ready();
    state = [for (final item in state) if (item.id != id) item];
    await _persist();
  }

  Future<void> discardAll() async {
    await ready();
    state = const [];
    await _persist();
  }
}

final pendingUploadsProvider =
    NotifierProvider<PendingUploadsNotifier, List<PendingUpload>>(
        PendingUploadsNotifier.new);

/// How many queued photos are still waiting on the network, for the badge on
/// the upload screen. Rejected items are excluded — those need a decision
/// from the farmer, not patience.
final pendingCountProvider = Provider<int>((ref) {
  final items = ref.watch(pendingUploadsProvider);
  return items.where((item) => !item.permanent).length;
});
