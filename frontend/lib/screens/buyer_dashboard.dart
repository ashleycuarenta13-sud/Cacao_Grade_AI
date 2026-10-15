import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/dashboard_shell.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// Buyer portal - Activity 2, Part A, actors:
/// **"Buyer (checks quality history)"**.
///
/// A buyer never uploads or grades cacao, so this portal is deliberately
/// read-only. The backend enforces the same rule: a `buyer` session may call
/// `GET /api/batches`, `GET /api/history` and `GET /api/trends`, but
/// `POST /api/classify` and `DELETE /api/batches/{id}` answer 403.
class BuyerDashboard extends ConsumerWidget {
  final AppUser user;
  const BuyerDashboard({super.key, required this.user});

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
      brandSubtitle: 'BUYER PORTAL',
      sectionLabel: 'BUYER WORKSPACE',
      breadcrumb: 'Workspace / Buyer Portal',
      footerText: 'CACAOGRADEAI · BUYER PORTAL',
      userIcon: Icons.shopping_basket_outlined,
      userName: user.name,
      userRole: user.role,
      items: const [
        NavItem(Icons.dashboard_outlined, 'Overview'),
        NavItem(Icons.workspace_premium_outlined, 'Quality History'),
        NavItem(Icons.agriculture_outlined, 'Farmer Directory'),
        NavItem(Icons.person_outline, 'My Profile'),
      ],
      titles: const [
        'Buyer Dashboard',
        'Quality History',
        'Farmer Directory',
        'My Profile',
      ],
      sidebarCard: const SidebarInfoCard(
        icon: Icons.verified_outlined,
        title: 'Buying on facts',
        body: 'Every grade below was produced by the cooperative from a stored cut-test photo, so the quality history is auditable.',
      ),
      pageBuilder: (context, i, goTo) {
        void view(Batch b) =>
            showDetailsDialog(context, 'Batch Details', batchDetailRows(b));

        switch (i) {
          case 1:
            return _QualityHistory(batches: batches, onView: view);
          case 2:
            return _Farmers(batches: batches);
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

  @override
  Widget build(BuildContext context) {
    final graded = batches.where((b) => b.stage != null).toList();
    final farmers = batches.map((b) => b.farmer).where((n) => n.isNotEmpty).toSet();
    final avg = trends?['average_confidence'];

    // Batches a careful buyer would want to look at twice: over-fermented,
    // or graded with less than half confidence.
    final caution = graded
        .where((b) =>
            b.stage == 'over_fermented' ||
            b.stage == 'partially_fermented' ||
            (b.confidence ?? 1) < 0.5)
        .toList();

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
          const Text('BUYER PORTAL',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: AppColors.dashGold,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Check quality history before you buy.',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
              'Grades come from the cooperative\'s cut-test records, not from a self-reported claim.',
              style: TextStyle(color: Colors.white70, height: 1.6)),
          const SizedBox(height: 18),
          PrimaryButton(
              label: 'Review Quality History',
              icon: Icons.arrow_forward,
              onPressed: () => goTo(1)),
        ]),
      ),
      const SizedBox(height: 26),
      SectionHeading(
        title: 'Quality Summary',
        subtitle: 'Read straight from the cooperative\'s PostgreSQL records.',
        trailing: Text(fmtDate(DateTime.now()),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
      ResponsiveGrid(minWidth: 220, children: [
        StatCard(
            label: 'Batches Available',
            icon: Icons.inventory_2_outlined,
            value: '${trends?['total_batches'] ?? batches.length}',
            caption: 'Lots you may inspect'),
        StatCard(
            label: 'Graded Records',
            icon: Icons.fact_check_outlined,
            value: '${trends?['total_records'] ?? graded.length}',
            caption: 'Cut-test results on file'),
        StatCard(
            label: 'Suppliers',
            icon: Icons.agriculture_outlined,
            value: '${farmers.length}',
            caption: 'Distinct farmer accounts'),
        if (avg is num)
          StatCard(
              label: 'Average Confidence',
              icon: Icons.speed_outlined,
              value: '${(avg * 100).toStringAsFixed(1)}%',
              caption: 'Model certainty across grades'),
      ]),
      const SizedBox(height: 22),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeading(
            compact: true,
            title: 'Batches Worth a Closer Look',
            subtitle:
                'Over-fermented, partially fermented, or low-confidence grades.',
            trailing: TextButton(
                onPressed: () => goTo(1), child: const Text('View All')),
          ),
          if (caution.isEmpty)
            const EmptyNote(
                'No batch currently carries an over-fermented, partially fermented, or low-confidence grade.')
          else
            for (final b in caution.take(5))
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

// ---------------- Quality History ----------------

class _QualityHistory extends StatefulWidget {
  final List<Batch> batches;
  final void Function(Batch) onView;
  const _QualityHistory({required this.batches, required this.onView});

  @override
  State<_QualityHistory> createState() => _QualityHistoryState();
}

class _QualityHistoryState extends State<_QualityHistory> {
  String _q = '';
  String _stage = 'all';

  static const _stages = <String, String>{
    'all': 'All Stages',
    'unfermented': 'Unfermented',
    'partially_fermented': 'Partially Fermented',
    'well_fermented': 'Well-Fermented',
    'over_fermented': 'Over-Fermented',
  };

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);

    final list = widget.batches.where((b) {
      final q = _q.toLowerCase();
      final okQ = q.isEmpty ||
          b.name.toLowerCase().contains(q) ||
          b.farmer.toLowerCase().contains(q) ||
          b.id.toLowerCase().contains(q);
      return okQ && (_stage == 'all' || b.stage == _stage);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(
          title: 'Quality History',
          subtitle:
              'Every batch the cooperative has graded, with its fermentation stage.'),
      SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search batch, supplier, or id',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: _stage,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final e in _stages.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _stage = v ?? 'all'),
                ),
              ]),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const EmptyNote(
                'No batch matches the current filters. Grades appear here once the cooperative runs a cut test.')
          else
            for (final b in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.name,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: p.text)),
                                  const SizedBox(height: 2),
                                  Text(
                                      b.farmer.isEmpty
                                          ? 'Supplier not recorded'
                                          : 'Supplied by ${b.farmer}',
                                      style: TextStyle(
                                          fontSize: 11.5, color: p.muted)),
                                ]),
                          ),
                          StatusBadge(b.status),
                        ]),
                        const SizedBox(height: 12),
                        Wrap(spacing: 34, runSpacing: 8, children: [
                          DetailRow('Fermentation Stage', b.stageLabel),
                          DetailRow('Model Confidence', b.confidenceLabel),
                          DetailRow('Graded', fmtDate(b.createdAt)),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                            b.recommendation ??
                                'No quality recommendation is on file for this batch.',
                            style:
                                TextStyle(fontSize: 12, height: 1.7, color: p.muted)),
                      ]),
                ),
              ),
        ]),
      ),
    ]);
  }
}

// ---------------- Farmer Directory ----------------

class _Farmers extends StatelessWidget {
  final List<Batch> batches;
  const _Farmers({required this.batches});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);

    // Group the batches the API already sent; no extra round-trip needed.
    final byFarmer = <String, List<Batch>>{};
    for (final b in batches) {
      final key = b.farmer.trim();
      if (key.isEmpty) continue;
      byFarmer.putIfAbsent(key, () => []).add(b);
    }

    final names = byFarmer.keys.toList()..sort();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeading(
          title: 'Farmer Directory',
          subtitle:
              'Which farms supplied the lots you are looking at, and how they graded.'),
      if (names.isEmpty)
        const SurfaceCard(
          child: EmptyNote(
              'No supplier names are attached to the current batches, so the directory cannot be built yet.'),
        )
      else
        SurfaceCard(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final name in names) _farmerTile(p, name, byFarmer[name]!),
              ]),
        ),
    ]);
  }

  Widget _farmerTile(Pal p, String name, List<Batch> lots) {
    final graded = lots.where((b) => b.stage != null).toList();
    final well = lots.where((b) => b.stage == 'well_fermented').length;
    final caution = lots
        .where((b) =>
            b.stage == 'over_fermented' || b.stage == 'partially_fermented')
        .length;
    final confidences = graded
        .map((b) => b.confidence)
        .whereType<double>()
        .toList();
    final avg = confidences.isEmpty
        ? null
        : confidences.reduce((a, b) => a + b) / confidences.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: p.soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  radius: 18,
                  backgroundColor: p.card,
                  child: Icon(Icons.agriculture_outlined,
                      size: 18, color: p.accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: p.text)),
              ),
              Text('${lots.length} batch${lots.length == 1 ? '' : 'es'}',
                  style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 30, runSpacing: 8, children: [
              DetailRow('Graded lots', '${graded.length}'),
              DetailRow('Well-fermented', '$well'),
              DetailRow('Needs caution', '$caution'),
              if (avg != null)
                DetailRow('Avg confidence', '${(avg * 100).toStringAsFixed(1)}%'),
            ]),
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
          subtitle: 'Buyer account information and portal access.'),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SurfaceCard(
            child: Column(children: [
              const CircleAvatar(
                  radius: 38,
                  backgroundColor: AppColors.forest,
                  child: Icon(Icons.shopping_basket_outlined,
                      size: 36, color: Colors.white)),
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
                  'Read-only access: buyers may review quality history but cannot upload photos, grade beans, or change batches.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.7, color: p.muted)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
