import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cacao/services/api_service.dart';
import 'package:cacao/widgets/dashboard_shell.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/providers/pending_uploads.dart';
import 'package:cacao/services/pick_image.dart';
import 'package:cacao/providers/state.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/widgets.dart';

class FarmerDashboard extends ConsumerWidget {
  final AppUser user;
  const FarmerDashboard({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardShell(
      brandSubtitle: 'FERMENTATION INTELLIGENCE',
      sectionLabel: 'WORKSPACE',
      breadcrumb: 'Workspace / Farmer Portal',
      footerText: 'CACAOGRADEAI · FARMER PORTAL',
      userIcon: Icons.agriculture,
      userName: user.name,
      userRole: user.role,
      items: const [
        NavItem(Icons.dashboard_outlined, 'Dashboard'),
        NavItem(Icons.photo_camera_outlined, 'Classify Beans'),
        NavItem(Icons.inventory_2_outlined, 'Batch History'),
        NavItem(Icons.person_outline, 'My Profile'),
      ],
      titles: const ['Farmer Dashboard', 'Classify Cacao Beans', 'Batch History', 'My Profile'],
      sidebarCard: const SidebarInfoCard(
        icon: Icons.support_agent,
        title: 'Need assistance?',
        body: 'Get help with cacao classification and quality assessment.\ncacaogradeai@gmail.com',
      ),
      pageBuilder: (context, i, goTo) {
        switch (i) {
          case 0:
            return _Overview(goTo: goTo);
          case 1:
            return _Classify(goTo: goTo);
          case 2:
            return const _History();
          default:
            return _Profile(user: user);
        }
      },
    );
  }
}

// ---------------- Overview ----------------
class _Overview extends ConsumerWidget {
  final void Function(int) goTo;
  const _Overview({required this.goTo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Everything on this screen comes from the server: `GET /api/batches` for
    // the records, `GET /api/trends` for the aggregation.
    final batchesAsync = ref.watch(serverBatchesProvider);
    final batches = switch (batchesAsync) {
      AsyncData(value: final list) => list,
      _ => const <Batch>[],
    };
    final trendsAsync = ref.watch(trendsProvider);
    final trends = switch (trendsAsync) {
      AsyncData(value: final t) => t,
      _ => null,
    };
    final pending = batches.where((b) => b.status == 'Pending').length;
    final totalRecords = trends?['total_records'] is num
        ? (trends!['total_records'] as num).toInt()
        : 0;
    final totalBatches = trends?['total_batches'] is num
        ? (trends!['total_batches'] as num).toInt()
        : batches.length;
    final avgConfidence = trends?['average_confidence'];
    final p = Pal.of(context);

    const cats = [
      ('Unfermented', 'Fermentation is not yet sufficiently developed.', 'unfermented-cacao.png'),
      ('Partially Fermented', 'Fermentation is incomplete or uneven.', 'partially-fermented.png'),
      ('Well-Fermented', 'Fermentation appears well developed.', 'well-fermented.png'),
      ('Over-Fermented', 'Possible over-fermentation; verify with quality checks.', 'over-fermented.png'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Welcome banner
      Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.forest, AppColors.forestLight]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CACAO QUALITY MANAGEMENT',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: AppColors.dashGold, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Good day, Farmer.',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                'Track your cacao batches, review fermentation stages, and organize your quality records in one place.',
                style: TextStyle(color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 18),
              PrimaryButton(label: 'Classify Cacao Beans', icon: Icons.add_a_photo_outlined, onPressed: () => goTo(1)),
            ]),
          ),
          if (MediaQuery.of(context).size.width > 760) ...[
            const SizedBox(width: 20),
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/images/cacao-hero.png', height: 170, fit: BoxFit.cover),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 26),
      SectionHeading(
        title: 'Overview',
        subtitle: 'Summary of your cacao classification activity.',
        trailing: Text(fmtDate(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
      ResponsiveGrid(minWidth: 240, children: [
        StatCard(label: 'Total Batches', icon: Icons.inventory_2_outlined, value: '$totalBatches', caption: 'Batch records stored in PostgreSQL'),
        StatCard(label: 'AI Classifications', icon: Icons.image_search, value: '$totalRecords', caption: 'Results saved by the classification API'),
        StatCard(label: 'Pending Records', icon: Icons.schedule, value: '$pending', caption: 'Batches awaiting classification'),
        if (avgConfidence is num)
          StatCard(
            label: 'Average Confidence',
            icon: Icons.speed_outlined,
            value: '${(avgConfidence * 100).toStringAsFixed(1)}%',
            caption: 'Server-side mean across your classifications',
          ),
      ]),
      const SizedBox(height: 22),
      ResponsiveGrid(minWidth: 460, children: [
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeading(compact: true, title: 'Fermentation Categories', subtitle: 'Classification stages supported by the system.'),
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/images/${c.$3}', width: 54, height: 54, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.$1, style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
                      Text(c.$2, style: TextStyle(fontSize: 11.5, color: p.muted)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeading(
              compact: true,
              title: 'Recent Batch Activity',
              subtitle: 'Your latest batch records.',
              trailing: TextButton(onPressed: () => goTo(2), child: const Text('View All')),
            ),
            if (batches.isEmpty)
              const EmptyNote('No batch records yet. Submit a cacao batch to get started.')
            else
              for (final b in batches.take(4)) RecordTile(batch: b),
          ]),
        ),
        TrendsCard(trends: trends, totalRecords: totalRecords),
      ]),
    ]);
  }
}

// ---------------- Classify ----------------
class _Classify extends ConsumerStatefulWidget {
  final void Function(int) goTo;
  const _Classify({required this.goTo});

  @override
  ConsumerState<_Classify> createState() => _ClassifyState();
}

class _ClassifyState extends ConsumerState<_Classify> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  Uint8List? _bytes;
  String? _fileName;
  int _size = 0;
  String _message = '';
  bool _isError = false;
  bool _busy = false;

  /// The payload the backend answered with, straight out of [CacaoApi.classify].
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _msg(String m, {bool error = false}) => setState(() {
        _message = m;
        _isError = error;
      });

  String _fmtSize(int b) =>
      b < 1024 * 1024 ? '${(b / 1024).toStringAsFixed(1)} KB' : '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';

  /// Part C's `ImagePickerButton` - the single path every way of getting a
  /// photo in (camera or gallery) takes, so validation cannot be bypassed by
  /// choosing one entry point over the other.
  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await pickCacaoImage(source);
      if (picked == null) return; // user cancelled - not a failure

      setState(() {
        _bytes = picked.bytes;
        _fileName = picked.fileName;
        _size = picked.size;
      });
      _msg('Image ready for submission.');
    } on ImagePickException catch (error) {
      _msg(error.message, error: true);
    } catch (_) {
      _msg('Could not read that image. Please try another one.', error: true);
    }
  }

  void _remove() {
    setState(() {
      _bytes = null;
      _fileName = null;
      _size = 0;
    });
    _msg('Selected image removed.');
  }

  String _stageLabel(String raw) => stageName(raw);

  /// Parks a photo in the pending queue instead of losing it.
  ///
  /// Activity 2, Part E: *"uploads must be queued or clearly flagged as
  /// pending rather than silently lost."* Called for every way a submission
  /// can fail, because the one outcome the document rules out is a farmer's
  /// cut-test photo disappearing with no trace.
  Future<void> _queue(
    Uint8List bytes,
    String name, {
    required String reason,
  }) async {
    await ref.read(pendingUploadsProvider.notifier).enqueue(
          imageBytes: bytes,
          fileName: _fileName ?? 'cut-test.jpg',
          batchName: name,
          notes: _notes.text.trim(),
          reason: reason,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _bytes = null;
      _fileName = null;
      _size = 0;
    });
    _msg('Kept in your pending queue. It will be submitted automatically '
        'once the classifier is reachable again — nothing was lost.');
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _msg('Please enter a batch name.', error: true);

    final bytes = _bytes;
    if (bytes == null) return _msg('Please choose a valid cacao photo.', error: true);

    setState(() {
      _busy = true;
      _result = null;
    });
    _msg('Uploading the cut-test photo to the classifier...');

    try {
      // Part D, steps 3-9: upload -> CNN -> business logic -> saved record.
      final result = await CacaoApi.classify(
        bytes: bytes,
        fileName: _fileName ?? 'cut-test.jpg',
        batchName: name,
        notes: _notes.text.trim(),
      );

      final stage = '${result['predicted_class']}';
      final confidence = result['confidence'] is num
          ? (result['confidence'] as num).toDouble()
          : null;

      // The backend already opened the batch and saved the record, so reload
      // both from the server instead of keeping a second copy on this device.
      ref.invalidate(serverBatchesProvider);
      ref.invalidate(trendsProvider);

      ref.read(activityProvider.notifier).log(
            'Cacao classified',
            '$name -> ${_stageLabel(stage)}'
                '${confidence == null ? '' : ' · ${(confidence * 100).toStringAsFixed(1)}%'}',
          );

      setState(() {
        _busy = false;
        _result = result;
      });
      _msg('Classification saved to your batch history.');
    } on ApiException catch (exc) {
      // A photo the classifier can still accept later is queued; one it could
      // not read at all is shown as an error, since replaying it would only
      // fail the same way.
      if (isRetryable(exc)) {
        await _queue(bytes, name, reason: exc.message);
      } else {
        setState(() => _busy = false);
        _msg(exc.message, error: true);
      }
    } catch (_) {
      setState(() => _busy = false);
      await _queue(bytes, name,
          reason: 'Failed before the server accepted the photo.');
    }
  }

  /// Renders the payload returned by `POST /api/classify`.
  Widget _resultCard(Pal p) {
    final result = _result;
    final stage = result == null ? null : '${result['predicted_class']}';
    final confidence = result != null && result['confidence'] is num
        ? (result['confidence'] as num).toDouble()
        : null;
    final imageUrl = '${result?['image_url'] ?? ''}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Classification Result',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
      Text('Generated on the server from the CNN prediction.',
          style: TextStyle(fontSize: 12, color: p.muted)),
      const SizedBox(height: 16),
      if (result == null)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Icon(Icons.find_in_page_outlined, size: 44, color: p.muted),
              const SizedBox(height: 8),
              Text('No Result Available',
                  style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 4),
              Text('Submit a batch and the fermentation stage will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
        )
      else ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.soft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FERMENTATION STAGE',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: p.muted)),
            Text(_stageLabel(stage!),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: p.text)),
            if (confidence != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: confidence.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: p.border,
                color: p.accent,
              ),
              const SizedBox(height: 4),
              Text('Confidence ${(confidence * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, color: p.muted)),
            ],
          ]),
        ),
        if ('${result['quality_notes'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 14),
          DetailRow('Quality notes', '${result['quality_notes']}'),
        ],
        if ('${result['recommendation'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          DetailRow('Recommendation', '${result['recommendation']}'),
        ],
        if (imageUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          DetailRow('Stored photo', imageUrl),
        ],
        if ('${result['engine'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          DetailRow('Inference engine', '${result['engine']}'),
        ],
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(title: 'Classify Cacao Beans', subtitle: 'Upload a cut-test photo to submit it for classification.'),
      ResponsiveGrid(minWidth: 460, children: [
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Photo Submission', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
            Text('Provide your batch information and cacao image.', style: TextStyle(fontSize: 12, color: p.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Batch Name *', hintText: 'e.g. Cacao Batch 001', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Batch Notes (optional)', hintText: 'Add location or fermentation notes', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _pick(ImageSource.gallery),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: p.soft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.border, width: 1.5),
                ),
                child: Column(children: [
                  Icon(Icons.cloud_upload_outlined, size: 38, color: p.accent),
                  const SizedBox(height: 6),
                  Text('Upload Cut-Test Photo', style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
                  Text('Choose a clear image of the cut cacao beans.', style: TextStyle(fontSize: 12, color: p.muted)),
                  Text('JPG or PNG · Maximum 10 MB', style: TextStyle(fontSize: 11, color: p.muted)),
                  const SizedBox(height: 12),
                  // Part C names this screen "Upload / Capture Bean Photo", so
                  // both ways of getting a photo in are offered side by side
                  // rather than hiding capture behind the file dialog.
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Capture Photo'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('Choose Image'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            if (_bytes != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_bytes!, width: 64, height: 64, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_fileName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
                    Text(_fmtSize(_size), style: TextStyle(fontSize: 11, color: p.muted)),
                  ]),
                ),
                IconButton(onPressed: _remove, icon: const Icon(Icons.close)),
              ]),
            ],
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_message, style: TextStyle(fontSize: 12, color: _isError ? AppColors.red : AppColors.green)),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: _busy ? 'Classifying...' : 'Submit Batch',
                icon: _busy ? Icons.hourglass_top : Icons.arrow_forward,
                onPressed: _busy ? null : _submit,
              ),
            ),
          ]),
        ),
        // Result panel, filled in by POST /api/classify.
        SurfaceCard(child: _resultCard(p)),
      ]),

      // Part E + reflection Q2: what the queue is holding, said plainly.
      const SizedBox(height: 18),
      const _PendingQueuePanel(),
    ]);
  }
}

/// Shows every cut-test photo the classifier has not been able to take yet.
///
/// Activity 2, Part E asks that an unavailable inference service results in
/// uploads being *"queued or clearly flagged as pending rather than silently
/// lost"*, and the reflection adds *"show a clear offline/pending status to
/// the user"*. This is that status.
class _PendingQueuePanel extends ConsumerWidget {
  const _PendingQueuePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Pal.of(context);
    final queue = ref.watch(pendingUploadsProvider);

    if (queue.isEmpty) return const SizedBox.shrink();

    final waiting = queue.where((item) => !item.permanent).length;
    final rejected = queue.length - waiting;
    final unpersisted = queue.any((item) => !item.persisted);

    Future<void> retryNow() async {
      final submitted =
          await ref.read(pendingUploadsProvider.notifier).flush();
      if (submitted == 0) return;
      ref.invalidate(serverBatchesProvider);
      ref.invalidate(trendsProvider);
      ref.read(activityProvider.notifier).log(
            'Pending uploads sent',
            '$submitted queued photo${submitted == 1 ? '' : 's'} '
                'classified once the service came back.',
          );
    }

    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.cloud_off_outlined, color: p.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Pending Uploads',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
          ),
          TextButton.icon(
            onPressed: queue.isEmpty ? null : retryNow,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry now'),
          ),
        ]),
        Text(
          waiting == 0
              ? '$rejected photo${rejected == 1 ? '' : 's'} could not be '
                  'classified. Nothing has been deleted — review and discard '
                  'them below when you are ready.'
              : '$waiting photo${waiting == 1 ? '' : 's'} waiting for the '
                  'classifier.'
                  '${rejected > 0 ? ' $rejected more could not be read.' : ''} '
                  'They are kept here and retried automatically.',
          style: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
        ),
        if (unpersisted)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'This device has no room left to store them, so they will only '
              'survive until the app is closed.',
              style: TextStyle(fontSize: 11, height: 1.5, color: AppColors.red),
            ),
          ),
        const SizedBox(height: 10),
        for (final item in queue)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.soft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: item.permanent ? AppColors.red : p.border),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(item.imageBytes,
                      width: 42, height: 42, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.batchName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: p.text)),
                        Text(
                          item.permanent
                              ? 'Rejected: ${item.lastError ?? 'could not be read'}'
                              : 'Waiting · attempt ${item.attempts}'
                                  '${item.lastError == null ? '' : ' · ${item.lastError}'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: item.permanent
                                  ? AppColors.red
                                  : p.muted),
                        ),
                      ]),
                ),
                IconButton(
                  tooltip: 'Discard this photo',
                  onPressed: () => ref
                      .read(pendingUploadsProvider.notifier)
                      .discard(item.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ---------------- History ----------------
class _History extends ConsumerWidget {
  const _History();

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Batch b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete batch?'),
        content: Text(
            'Remove "${b.name}" and its classification records from the server?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;

    final id = int.tryParse(b.id);
    if (id == null) return;

    try {
      await CacaoApi.deleteBatch(id);
      ref.invalidate(serverBatchesProvider);
      ref.invalidate(trendsProvider);
    } on ApiException catch (exc) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(exc.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(serverBatchesProvider);
    final batches = switch (async) {
      AsyncData(value: final list) => list,
      _ => const <Batch>[],
    };
    final error = async.error;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeading(
        title: 'Batch History',
        subtitle: 'Batch records stored in PostgreSQL.',
        trailing: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54)),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
          onPressed: () {
            ref.invalidate(serverBatchesProvider);
            ref.invalidate(trendsProvider);
          },
        ),
      ),
      SurfaceCard(
        child: async.isLoading
            ? const EmptyNote('Loading batch history from the server...')
            : error != null
                ? EmptyNote('$error')
                : batches.isEmpty
                    ? const EmptyNote(
                        'No batch records found. Your submitted batches will appear here.')
                    : Column(children: [
                        for (final b in batches)
                          RecordTile(
                              batch: b,
                              onTap: () => _confirmDelete(context, ref, b)),
                      ]),
      ),
    ]);
  }
}

// ---------------- Profile ----------------
class _Profile extends StatelessWidget {
  final AppUser user;
  const _Profile({required this.user});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l, style: TextStyle(color: p.muted, fontSize: 13)),
            Text(v, style: TextStyle(color: p.text, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(title: 'My Profile', subtitle: 'Farmer account information.'),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SurfaceCard(
            child: Column(children: [
              CircleAvatar(radius: 38, backgroundColor: AppColors.forest, child: const Icon(Icons.agriculture, size: 36, color: Colors.white)),
              const SizedBox(height: 12),
              Text(user.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
              Text(user.email, style: TextStyle(color: p.muted)),
              Divider(height: 28, color: p.border),
              row('Account Role', user.role),
              row('System', 'CacaoGradeAI'),
            ]),
          ),
        ),
      ),
    ]);
  }
}
