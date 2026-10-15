import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_service.dart';
import '../core/dashboard_shell.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class AdminDashboard extends ConsumerWidget {
  final AppUser user;
  const AdminDashboard({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Server-backed: every batch plus the backend's trend aggregation.
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
    final users = ref.watch(usersProvider);
    final activity = ref.watch(activityProvider);

    return DashboardShell(
      brandSubtitle: 'ADMINISTRATION PORTAL',
      sectionLabel: 'ADMIN WORKSPACE',
      breadcrumb: 'Workspace / Administration',
      footerText: 'CACAOGRADEAI · ADMIN PORTAL',
      userIcon: Icons.admin_panel_settings_outlined,
      userName: user.name,
      userRole: user.role,
      items: const [
        NavItem(Icons.dashboard_outlined, 'Overview'),
        NavItem(Icons.group_outlined, 'User Management'),
        NavItem(Icons.inventory_2_outlined, 'Batch Management'),
        NavItem(Icons.biotech_outlined, 'Classifications'),
        NavItem(Icons.manage_history, 'System Activity'),
        NavItem(Icons.admin_panel_settings_outlined, 'My Profile'),
      ],
      titles: const ['Admin Dashboard', 'User Management', 'Batch Management', 'Classification Monitoring', 'System Activity', 'My Profile'],
      sidebarCard: const SidebarInfoCard(
        icon: Icons.shield_outlined,
        title: 'System Administration',
        body: 'Manage users and monitor cacao quality records responsibly.',
      ),
      pageBuilder: (context, i, goTo) {
        void viewBatch(Batch b) {
          ref.read(activityProvider.notifier).log('Viewed batch', b.name);
          showDetailsDialog(context, 'Record Details', batchDetailRows(b));
        }

        switch (i) {
          case 0:
            return _Overview(batches: batches, trends: trends, users: users, activity: activity, goTo: goTo, onView: viewBatch);
          case 1:
            return _Users(users: users, refresh: () => refreshUsers(ref));
          case 2:
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeading(title: 'Batch Management', subtitle: 'Review submitted batch records and their current status.'),
              BatchBrowser(batches: batches, onView: viewBatch),
            ]);
          case 3:
            return _Classifications(batches: batches);
          case 4:
            return _Activity(activity: activity);
          default:
            return _Profile(user: user);
        }
      },
    );
  }
}

class _ActivityList extends StatelessWidget {
  final List<ActivityItem> items;
  const _ActivityList(this.items);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (items.isEmpty) return const EmptyNote('No activity recorded yet.');
    return Column(children: [
      for (final a in items)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
          child: Row(children: [
            Icon(Icons.history, size: 20, color: p.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.action, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.text)),
                Text(a.details, style: TextStyle(fontSize: 11.5, color: p.muted)),
              ]),
            ),
            Text(fmtDate(a.time), style: TextStyle(fontSize: 11, color: p.muted)),
          ]),
        ),
    ]);
  }
}

class _Overview extends StatelessWidget {
  final List<Batch> batches;
  final Map<String, dynamic>? trends;
  final List<AppUser> users;
  final List<ActivityItem> activity;
  final void Function(int) goTo;
  final void Function(Batch) onView;
  const _Overview(
      {required this.batches,
      this.trends,
      required this.users,
      required this.activity,
      required this.goTo,
      required this.onView});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    int bc(String s) => batches.where((b) => b.status == s).length;
    int uc(String r) => users.where((u) => u.role == r).length;
    final total = batches.isEmpty ? 1 : batches.length;

    Widget bar(String label, int n, Color c) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, color: p.text)),
              ]),
              Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: n / total, minHeight: 8, color: c, backgroundColor: p.soft),
            ),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.forest, AppColors.forestLight]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SYSTEM ADMINISTRATION',
              style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: AppColors.dashGold, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Manage your system with confidence.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Monitor user accounts, oversee cacao batch records, and review classification activity from one workspace.',
              style: TextStyle(color: Colors.white70, height: 1.6)),
          const SizedBox(height: 18),
          PrimaryButton(label: 'Manage Users', icon: Icons.manage_accounts_outlined, onPressed: () => goTo(1)),
        ]),
      ),
      const SizedBox(height: 26),
      SectionHeading(
        title: 'System Overview',
        subtitle: 'Summary computed by the backend from PostgreSQL.',
        trailing: Text(fmtDate(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
      ResponsiveGrid(minWidth: 220, children: [
        StatCard(label: 'Total Users', icon: Icons.group_outlined, value: '${users.length}', caption: 'Accounts in the user directory'),
        StatCard(label: 'Farmers', icon: Icons.agriculture, value: '${uc('Farmer')}', caption: 'Farmer accounts'),
        StatCard(label: 'Staff', icon: Icons.badge_outlined, value: '${uc('Staff')}', caption: 'Staff accounts'),
        StatCard(label: 'Total Batches', icon: Icons.inventory_2_outlined, value: '${trends?['total_batches'] ?? batches.length}', caption: 'Available batch records'),
      ]),
      const SizedBox(height: 22),
      ResponsiveGrid(minWidth: 460, children: [
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeading(compact: true, title: 'Batch Status', subtitle: 'Current status of available batch records.'),
            bar('Pending', bc('Pending'), AppColors.amber),
            bar('Classified', bc('Classified'), AppColors.green),
            bar('Flagged', bc('Flagged'), AppColors.red),
          ]),
        ),
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeading(
              compact: true,
              title: 'Recent Activity',
              subtitle: 'Latest actions recorded on this device.',
              trailing: TextButton(onPressed: () => goTo(4), child: const Text('View All')),
            ),
            _ActivityList(activity.take(4).toList()),
          ]),
        ),
      ]),
      const SizedBox(height: 22),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
            compact: true,
            title: 'Recent Batch Records',
            subtitle: 'Recently submitted cacao batches.',
            trailing: TextButton(onPressed: () => goTo(2), child: const Text('View All')),
          ),
          if (batches.isEmpty)
            const EmptyNote('No batch records available.')
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

class _Users extends StatefulWidget {
  final List<AppUser> users;
  final Future<void> Function() refresh;
  const _Users({required this.users, required this.refresh});

  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  String _q = '';
  String _role = 'all';

  /// Which account row is currently waiting on `PATCH /api/admin/users/{id}`.
  int? _busyId;

  /// Activity 2, Part A - "Administrator (manages users/settings)".
  /// The five documented actors are assigned here; the backend refuses an
  /// unknown slug and refuses an administrator demoting themselves.
  Future<void> _setRole(BuildContext context, AppUser u, String label) async {
    final id = int.tryParse(u.id);
    final slug = roleSlug(label);

    if (id == null || slug == u.roleKey) return;

    // Captured before the first await, so the snackbar never depends on a
    // context that has been suspended across an async gap.
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busyId = id);

    try {
      await CacaoApi.updateUserRole(id, slug);
      messenger.showSnackBar(
        SnackBar(content: Text('${u.name} is now a ${roleLabel(slug)}.')),
      );
      await widget.refresh();
    } on ApiException catch (exc) {
      messenger.showSnackBar(SnackBar(content: Text(exc.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = widget.users.where((u) {
      final q = _q.toLowerCase();
      final okQ = q.isEmpty || u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q) || u.id.toLowerCase().contains(q);
      return okQ && (_role == 'all' || u.role == _role);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(
        title: 'User Management',
        subtitle: 'Assign one of the five documented roles (Farmer, Cooperative Staff, Buyer, Agricultural Extension Worker, Administrator). Only administrators may change a role.',
      ),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, email, or ID',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            DropdownButton<String>(
              value: _role,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All Roles')),
                for (final r in kRoleLabels)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'all'),
            ),
          ]),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const EmptyNote('No user records found.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.muted),
                columns: const [
                  DataColumn(label: Text('USER')),
                  DataColumn(label: Text('EMAIL')),
                  DataColumn(label: Text('ROLE')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('ACTION')),
                ],
                rows: [
                  for (final u in list)
                    DataRow(cells: [
                      DataCell(Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                      DataCell(Text(u.email, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(u.role, style: const TextStyle(fontSize: 12))),
                      DataCell(Text(u.status, style: const TextStyle(fontSize: 12))),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          child: const Text('View'),
                          onPressed: () => showDetailsDialog(context, 'User Details', [
                            DetailRow('Name', u.name),
                            DetailRow('Email', u.email),
                            DetailRow('Role', u.role),
                            DetailRow('Status', u.status),
                            DetailRow('User ID', u.id),
                          ]),
                        ),
                        if (_busyId == int.tryParse(u.id))
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          DropdownButton<String>(
                            value: kRoleLabels.contains(u.role) ? u.role : 'Farmer',
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final r in kRoleLabels)
                                DropdownMenuItem(
                                    value: r,
                                    child:
                                        Text(r, style: const TextStyle(fontSize: 12))),
                            ],
                            onChanged: (v) =>
                                v == null ? null : _setRole(context, u, v),
                          ),
                      ])),
                    ]),
                ],
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _Classifications extends StatelessWidget {
  final List<Batch> batches;
  const _Classifications({required this.batches});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = batches.where((b) => b.status != 'Pending').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(title: 'Classification Monitoring', subtitle: 'Review results returned by the classification model.'),
      SurfaceCard(
        child: list.isEmpty
            ? const EmptyNote('No classification results are available yet. Results will appear here once the backend returns them.')
            : Column(children: [
                for (final b in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.name, style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
                          Text('${b.stageLabel} · ${b.confidenceLabel}', style: TextStyle(fontSize: 12, color: p.muted)),
                        ]),
                      ),
                      StatusBadge(b.status),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

class _Activity extends ConsumerWidget {
  final List<ActivityItem> activity;
  const _Activity({required this.activity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeading(
        title: 'System Activity',
        subtitle: 'Actions recorded on this device.',
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
          onPressed: activity.isEmpty ? null : () => ref.read(activityProvider.notifier).clear(),
          child: const Text('Clear Activity'),
        ),
      ),
      SurfaceCard(child: _ActivityList(activity)),
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
      const SectionHeading(title: 'My Profile', subtitle: 'Administrator account information.'),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SurfaceCard(
            child: Column(children: [
              const CircleAvatar(radius: 38, backgroundColor: AppColors.forest, child: Icon(Icons.admin_panel_settings_outlined, size: 36, color: Colors.white)),
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
