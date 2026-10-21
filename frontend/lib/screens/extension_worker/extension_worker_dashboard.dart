import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cacao/widgets/dashboard_shell.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/providers/state.dart';
import 'package:cacao/theme.dart';
import 'package:cacao/widgets/widgets.dart';

/// Agricultural extension worker portal - Activity 2, Part A, actors:
/// **"Agricultural extension worker (monitors multiple farmer accounts)"**.
///
/// The point of this portal is the per-account roll-up, so everything is
/// grouped by the batch's owner. Like the buyer role it is read-only: the
/// backend answers 403 for `POST /api/classify` and `DELETE /api/batches/{id}`
/// on an `extension_worker` session, while `GET /api/batches` and
/// `GET /api/history` return every account rather than only the caller's.
class ExtensionWorkerDashboard extends ConsumerWidget {
  final AppUser user;
  const ExtensionWorkerDashboard({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return DashboardShell(
      brandSubtitle: 'EXTENSION WORKER PORTAL',
      sectionLabel: 'ADVISORY WORKSPACE',
      breadcrumb: 'Workspace / Extension Services',
      footerText: 'CACAOGRADEAI · EXTENSION PORTAL',
      userIcon: Icons.school_outlined,
      userName: user.name,
      userRole: user.role,
      items: const [
        NavItem(Icons.dashboard_outlined, 'Overview'),
        NavItem(Icons.groups_outlined, 'Farmer Accounts'),
        NavItem(Icons.history, 'Batch History'),
        NavItem(Icons.person_outline, 'My Profile'),
      ],
      titles: const [
        'Advisory Dashboard',
        'Farmer Accounts',
        'Batch History',
        'My Profile',
      ],
      sidebarCard: const SidebarInfoCard(
        icon: Icons.insights_outlined,
        title: 'Advisory view',
        body: 'Compare fermentation practices across the accounts you advise and see which farms need a visit.',
      ),
      pageBuilder: (context, i, goTo) {
        void view(Batch b) =>
            showDetailsDialog(context, 'Batch Details', batchDetailRows(b));

        switch (i) {
          case 1:
            return _Accounts(batches: batches, onView: view);
          case 2:
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading(
                      title: 'Batch History',
                      subtitle:
                          'Every batch across the accounts you monitor.'),
                  BatchBrowser(batches: batches, onView: view),
                ]);
          case 3:
            return _Profile(user: user);
          default:
            return _Overview(
                batches: batches, trends: trends, goTo: goTo, onView: view);
        }
      },
    );
  }
}

// ---------------- Overview ----------------

class _Overview extends StatelessWidget {
  final List<Batch> batches;
  final Map<String, dynamic>? trends;
  final void Function(int) goTo;
  final void Function(Batch) onView;
  const _Overview(
      {required this.batches,
      this.trends,
      required this.goTo,
      required this.onView});

  /// Accounts that hold a batch but have never had one graded yet - the
  /// farms most in need of an introduction to the cut-test workflow.
  List<String> get _inactive {
    final byFarmer = <String, List<Batch>>{};
    for (final b in batches) {
      final key = b.farmer.trim();
      if (key.isEmpty) continue;
      byFarmer.putIfAbsent(key, () => []).add(b);
    }
    return byFarmer.entries
        .where((e) => e.value.every((b) => b.stage == null))
        .map((e) => e.key)
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final avg = trends?['average_confidence'];

    final farmers =
        batches.map((b) => b.farmer).where((n) => n.trim().isNotEmpty).toSet();
    final recent = List<Batch>.from(batches)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final idle = _inactive;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [AppColors.forest, AppColors.forestLight]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('EXTENSION SERVICES',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: AppColors.dashGold,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Monitor the farms you advise.',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
              'One advisory dashboard across every farmer account, built from the same cut-test records the cooperative stores.',
              style: TextStyle(color: Colors.white70, height: 1.6)),
          const SizedBox(height: 18),
          PrimaryButton(
              label: 'Review Farmer Accounts',
              icon: Icons.arrow_forward,
              onPressed: () => goTo(1)),
        ]),
      ),
      const SizedBox(height: 26),
      SectionHeading(
        title: 'Coverage Overview',
        subtitle: 'Aggregated by the backend across every monitored account.',
        trailing: Text(fmtDate(DateTime.now()),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
      ResponsiveGrid(minWidth: 220, children: [
        StatCard(
            label: 'Farmer Accounts',
            icon: Icons.groups_outlined,
            value: '${farmers.length}',
            caption: 'Farms appearing in the records'),
        StatCard(
            label: 'Batches Monitored',
            icon: Icons.inventory_2_outlined,
            value: '${trends?['total_batches'] ?? batches.length}',
            caption: 'Lots across all accounts'),
        StatCard(
            label: 'Cut Tests Run',
            icon: Icons.fact_check_outlined,
            value: '${trends?['total_records'] ?? 0}',
            caption: 'Classification records on file'),
        if (avg is num)
          StatCard(
              label: 'Average Confidence',
              icon: Icons.speed_outlined,
              value: '${(avg * 100).toStringAsFixed(1)}%',
              caption: 'Model certainty across accounts'),
      ]),
      const SizedBox(height: 22),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
            compact: true,
            title: 'Accounts With No Cut Test Yet',
            subtitle: 'Farms holding batches that have never been graded.',
            trailing: TextButton(
                onPressed: () => goTo(1), child: const Text('View Accounts')),
          ),
          if (idle.isEmpty)
            const EmptyNote(
                'Every monitored account has at least one graded batch.')
          else
            Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final name in idle)
                    Chip(
                      avatar: const Icon(Icons.warning_amber_outlined,
                          size: 18, color: AppColors.dashGold),
                      label: Text(name),
                      backgroundColor: p.soft,
                      side: BorderSide(color: p.border),
                    ),
                ]),
        ]),
      ),
      const SizedBox(height: 22),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
            compact: true,
            title: 'Most Recent Submissions',
            subtitle: 'Latest activity across every monitored account.',
            trailing: TextButton(
                onPressed: () => goTo(2), child: const Text('View All')),
          ),
          if (recent.isEmpty)
            const EmptyNote('No batches have been submitted yet.')
          else
            for (final b in recent.take(5))
              RecordTile(batch: b, onTap: () => onView(b)),
        ]),
      ),
      const SizedBox(height: 22),
      TrendsCard(
        trends: trends,
        totalRecords: trends?['total_records'] is num
            ? (trends!['total_records'] as num).toInt()
            : batches.length,
      ),
    ]);
  }
}

// ---------------- Farmer Accounts ----------------

class _Accounts extends StatelessWidget {
  final List<Batch> batches;
  final void Function(Batch) onView;
  const _Accounts({required this.batches, required this.onView});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);

    final byFarmer = <String, List<Batch>>{};
    for (final b in batches) {
      final key = b.farmer.trim();
      if (key.isEmpty) continue;
      byFarmer.putIfAbsent(key, () => []).add(b);
    }

    final names = byFarmer.keys.toList()..sort();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(
          title: 'Farmer Accounts',
          subtitle:
              'Each account you advise, with its grading coverage and latest result.'),
      if (names.isEmpty)
        const SurfaceCard(
          child: EmptyNote(
              'No batch in the current records carries an owner name, so accounts cannot be grouped yet.'),
        )
      else
        Column(children: [
          for (final name in names)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _accountCard(p, name, byFarmer[name]!),
            ),
        ]),
    ]);
  }

  Widget _accountCard(Pal p, String name, List<Batch> lots) {
    final latest = List<Batch>.from(lots)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final graded = lots.where((b) => b.stage != null).length;
    final well = lots.where((b) => b.stage == 'well_fermented').length;
    final over = lots.where((b) => b.stage == 'over_fermented').length;
    final coverage = lots.isEmpty ? 0.0 : graded / lots.length;

    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: p.soft,
              child:
                  Icon(Icons.agriculture_outlined, size: 18, color: p.accent)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
          ),
          Text('Last activity ${fmtDate(latest.first.createdAt)}',
              style: TextStyle(fontSize: 11, color: p.muted)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 34, runSpacing: 8, children: [
          DetailRow('Batches', '${lots.length}'),
          DetailRow('Graded', '$graded'),
          DetailRow('Well-fermented', '$well'),
          DetailRow('Over-fermented', '$over'),
        ]),
        const SizedBox(height: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Grading coverage',
                style: TextStyle(fontSize: 11.5, color: p.muted)),
            Text('${(coverage * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: p.text)),
          ]),
          const SizedBox(height: 5),
          LinearProgressIndicator(
              value: coverage,
              minHeight: 6,
              backgroundColor: p.border,
              color: over > 0 ? AppColors.dashGold : p.accent),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('Latest batch'),
            onPressed: () => onView(latest.first),
          ),
        ),
      ]),
    );
  }
}

// ---------------- Profile ----------------

class _Profile extends StatelessWidget {
  final AppUser user;
  const _Profile({required this.user});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(
          title: 'My Profile',
          subtitle: 'Extension worker account information and portal access.'),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SurfaceCard(
            child: Column(children: [
              const CircleAvatar(
                  radius: 38,
                  backgroundColor: AppColors.forest,
                  child: Icon(Icons.school_outlined, size: 36, color: Colors.white)),
              const SizedBox(height: 12),
              Text(user.name,
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
              Text(user.email, style: TextStyle(color: p.muted)),
              Divider(height: 28, color: p.border),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Account Role', style: TextStyle(color: p.muted)),
                Text(user.role,
                    style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
              ]),
              const SizedBox(height: 10),
              Text(
                  'Read-only access: extension workers see every farmer account, but cannot upload photos, grade beans, or change batches.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.7, color: p.muted)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
