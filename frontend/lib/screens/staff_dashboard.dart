import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/dashboard_shell.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class StaffDashboard extends ConsumerWidget {
  final AppUser user;
  const StaffDashboard({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Server-backed: every batch a cooperative staff member may review,
    // plus the backend's own trend aggregation.
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
      brandSubtitle: 'STAFF PORTAL',
      sectionLabel: 'STAFF WORKSPACE',
      breadcrumb: 'Workspace / Staff Portal',
      footerText: 'CACAOGRADEAI · STAFF PORTAL',
      userIcon: Icons.badge_outlined,
      userName: user.name,
      userRole: user.role,
      items: const [
        NavItem(Icons.dashboard_outlined, 'Overview'),
        NavItem(Icons.inventory_2_outlined, 'Batch Management'),
        NavItem(Icons.fact_check_outlined, 'Classification Review'),
        NavItem(Icons.history, 'Batch History'),
        NavItem(Icons.person_outline, 'My Profile'),
      ],
      titles: const ['Staff Dashboard', 'Batch Management', 'Classification Review', 'Batch History', 'My Profile'],
      sidebarCard: const SidebarInfoCard(
        icon: Icons.verified_outlined,
        title: 'Quality Review',
        body: 'Review submitted batches and classification results.',
      ),
      pageBuilder: (context, i, goTo) {
        void view(Batch b) => showDetailsDialog(context, 'Batch Details', batchDetailRows(b));
        switch (i) {
          case 0:
            return _Overview(batches: batches, trends: trends, goTo: goTo, onView: view);
          case 1:
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeading(title: 'Batch Management', subtitle: 'Review submitted batch records and their current status.'),
              BatchBrowser(batches: batches, onView: view),
            ]);
          case 2:
            return _Review(batches: batches);
          case 3:
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeading(title: 'Batch History', subtitle: 'All batch records stored in PostgreSQL.'),
              SurfaceCard(
                child: batches.isEmpty
                    ? const EmptyNote('No batch history is available on this device.')
                    : Column(children: [for (final b in batches) RecordTile(batch: b, onTap: () => view(b))]),
              ),
            ]);
          default:
            return _Profile(user: user);
        }
      },
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    int count(String s) => batches.where((b) => b.status == s).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.forest, AppColors.forestLight]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('STAFF WORKSPACE',
              style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: AppColors.dashGold, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Welcome to your workspace.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Monitor submitted cacao batches and review classification results in one place.',
              style: TextStyle(color: Colors.white70, height: 1.6)),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Manage Batches', icon: Icons.arrow_forward, onPressed: () => goTo(1)),
        ]),
      ),
      const SizedBox(height: 26),
      SectionHeading(
        title: 'System Overview',
        subtitle: 'Summary computed by the backend from PostgreSQL.',
        trailing: Text(fmtDate(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
      ResponsiveGrid(minWidth: 220, children: [
        StatCard(label: 'Total Batches', icon: Icons.inventory_2_outlined, value: '${trends?['total_batches'] ?? batches.length}', caption: 'All submitted records'),
        StatCard(label: 'Pending', icon: Icons.schedule, value: '${count('Pending')}', caption: 'Awaiting classification'),
        StatCard(label: 'Classified', icon: Icons.task_alt, value: '${count('Classified')}', caption: 'Results received'),
        StatCard(label: 'Quality Flags', icon: Icons.flag_outlined, value: '${count('Flagged')}', caption: 'Needs attention'),
      ]),
      const SizedBox(height: 22),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
            compact: true,
            title: 'Recent Batch Submissions',
            subtitle: 'Latest records from farmers.',
            trailing: TextButton(onPressed: () => goTo(1), child: const Text('View All')),
          ),
          if (batches.isEmpty)
            const EmptyNote('No batch submissions yet.')
          else
            for (final b in batches.take(5)) RecordTile(batch: b, onTap: () => onView(b)),
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

class _Review extends StatelessWidget {
  final List<Batch> batches;
  const _Review({required this.batches});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = batches.where((b) => b.status == 'Classified' || b.status == 'Flagged').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(title: 'Classification Review', subtitle: 'Review completed classification results.'),
      if (list.isEmpty)
        const SurfaceCard(
          child: EmptyNote('There are no completed classification results to review. Pending batches will appear here after the backend returns classification results.'),
        )
      else
        Column(children: [
          for (final b in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SurfaceCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
                        Text(fmtDate(b.createdAt), style: TextStyle(fontSize: 11, color: p.muted)),
                      ]),
                    ),
                    StatusBadge(b.status),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 40, runSpacing: 8, children: [
                    DetailRow('Classification Stage', b.stageLabel),
                    DetailRow('Model Confidence', b.confidenceLabel),
                  ]),
                  const SizedBox(height: 6),
                  Text(b.recommendation ?? 'No quality recommendation is available.',
                      style: TextStyle(fontSize: 12, height: 1.7, color: p.muted)),
                ]),
              ),
            ),
        ]),
    ]);
  }
}

class _Profile extends StatelessWidget {
  final AppUser user;
  const _Profile({required this.user});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(title: 'My Profile', subtitle: 'Staff account information.'),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SurfaceCard(
            child: Column(children: [
              const CircleAvatar(radius: 38, backgroundColor: AppColors.forest, child: Icon(Icons.badge_outlined, size: 36, color: Colors.white)),
              const SizedBox(height: 12),
              Text(user.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
              Text(user.email, style: TextStyle(color: p.muted)),
              Divider(height: 28, color: p.border),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Account Role', style: TextStyle(color: p.muted)),
                Text(user.role, style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}
