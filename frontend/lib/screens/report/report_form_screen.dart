import 'package:flutter/material.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/widgets.dart';

/// Activity 9 - Report Form with the four async UI states.
/// NOTE: the submit is SIMULATED with Future.delayed (no REST API / PostgreSQL yet).
enum ReportUiState { idle, loading, success, empty, error, list }

class _Report {
  final String title;
  final String category;
  final String location;
  final DateTime createdAt;
  const _Report(this.title, this.category, this.location, this.createdAt);
}

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  static const _categories = [
    'Wrong Grade Result',
    'Image Upload Problem',
    'Batch Record Issue',
    'Other',
  ];

  String? _category;
  ReportUiState _uiState = ReportUiState.idle;
  bool _simulateFailure = false; // demo switch so the Error state can be shown
  final List<_Report> _reports = []; // starts empty -> Empty state

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_uiState == ReportUiState.loading) return; // block duplicate submits
    if (!_formKey.currentState!.validate()) return;

    setState(() => _uiState = ReportUiState.loading);
    try {
      await Future<void>.delayed(
        const Duration(seconds: 4),
      ); // simulated request
      if (_simulateFailure) throw Exception('Simulated failure');
      if (!mounted) return;
      _reports.insert(
        0,
        _Report(
          _titleCtrl.text.trim(),
          _category!,
          _locationCtrl.text.trim(),
          DateTime.now(),
        ),
      );
      setState(() => _uiState = ReportUiState.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uiState = ReportUiState.error);
    }
  }

  void _retry() {
    // Retry keeps what the user typed. Turning the demo switch off lets the
    // retry succeed, which shows that Retry really works.
    setState(() => _simulateFailure = false);
    _submit();
  }

  void _newReport() {
    _titleCtrl.clear();
    _descCtrl.clear();
    _locationCtrl.clear();
    setState(() {
      _category = null;
      _uiState = ReportUiState.idle;
    });
  }

  void _openList() => setState(
    () =>
        _uiState = _reports.isEmpty ? ReportUiState.empty : ReportUiState.list,
  );

  void _backToForm() => setState(() => _uiState = ReportUiState.idle);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report an Issue'),
        actions: [
          TextButton.icon(
            onPressed: _uiState == ReportUiState.loading ? null : _openList,
            icon: const Icon(Icons.list_alt),
            label: const Text('My Reports'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: switch (_uiState) {
              ReportUiState.success => _successView(),
              ReportUiState.empty => _emptyView(),
              ReportUiState.list => _listView(),
              _ => _formView(), // idle, loading, error keep the form visible
            },
          ),
        ),
      ),
    );
  }

  // ---------------- FORM (idle / loading / error) ----------------
  Widget _formView() {
    final p = Pal.of(context);
    final loading = _uiState == ReportUiState.loading;

    return SurfaceCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              compact: true,
              title: 'New Report',
              subtitle:
                  'Tell us about a problem with a batch or a grading result.',
            ),
            if (_uiState == ReportUiState.error) _errorBanner(),
            TextFormField(
              controller: _titleCtrl,
              enabled: !loading,
              decoration: const InputDecoration(
                labelText: 'Report Title',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Please enter a title.';
                if (t.length < 5) return 'Title must be at least 5 characters.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: loading ? null : (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Please choose a category.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _locationCtrl,
              enabled: !loading,
              decoration: const InputDecoration(
                labelText: 'Location / Batch Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter the location or batch name.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descCtrl,
              enabled: !loading,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Please describe the problem.';
                if (t.length < 15) {
                  return 'Add a bit more detail (15+ characters).';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate failure (demo only)'),
              subtitle: Text(
                'Turn on to show the Error state.',
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
              value: _simulateFailure,
              onChanged: loading
                  ? null
                  : (v) => setState(() => _simulateFailure = v),
            ),
            const SizedBox(height: 10),
            // Button is disabled (onPressed: null) while loading -> no duplicate submit.
            PrimaryButton(
              label: loading ? 'Submitting...' : 'Submit Report',
              icon: loading ? null : Icons.send,
              onPressed: loading ? null : _submit,
            ),
            if (loading) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Submitting your report, please wait...',
                      style: TextStyle(fontSize: 13, color: p.text),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- ERROR banner (inside the form) ----------------
  Widget _errorBanner() {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'We could not submit your report.',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: p.text,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The (simulated) request failed. Your answers are still here, '
            'so you can retry or correct them.',
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => setState(() => _uiState = ReportUiState.idle),
                child: const Text('Edit details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- SUCCESS ----------------
  Widget _successView() {
    final p = Pal.of(context);
    return SurfaceCard(
      child: Column(
        children: [
          const Icon(Icons.check_circle, size: 56, color: AppColors.green),
          const SizedBox(height: 12),
          Text(
            'Report submitted!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Thank you. Your report was recorded (simulated, not saved to a '
            'database yet).',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              PrimaryButton(
                label: 'Submit Another',
                icon: Icons.add,
                onPressed: _newReport,
              ),
              OutlinedButton(
                onPressed: _openList,
                child: const Text('View My Reports'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- EMPTY ----------------
  Widget _emptyView() {
    final p = Pal.of(context);
    return SurfaceCard(
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: p.muted),
          const SizedBox(height: 12),
          Text(
            'No reports yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You have not submitted any report. Create your first one now.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Create a Report',
            icon: Icons.add,
            onPressed: _backToForm,
          ),
        ],
      ),
    );
  }

  // ---------------- LIST (has records) ----------------
  Widget _listView() {
    final p = Pal.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            compact: true,
            title: 'My Reports',
            subtitle: 'Reports submitted in this session (simulated).',
          ),
          for (final r in _reports)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: p.soft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: p.text,
                    ),
                  ),
                  Text(
                    '${r.category} · ${r.location} · ${fmtDate(r.createdAt)}',
                    style: TextStyle(fontSize: 11, color: p.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          PrimaryButton(
            label: 'New Report',
            icon: Icons.add,
            onPressed: _newReport,
          ),
        ],
      ),
    );
  }
}
