import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cacao/models/models.dart';
import 'package:cacao/theme.dart';

String fmtDate(DateTime d) => DateFormat('MMM d, y').format(d);

/// Fermentation trend bars built from `GET /api/trends`.
///
/// Part A - business logic: "aggregation of batch/fermentation trend data for
/// the dashboard". The arithmetic happens on the server; this only draws it.
class TrendsCard extends StatelessWidget {
  final Map<String, dynamic>? trends;
  final int totalRecords;
  const TrendsCard({super.key, required this.trends, required this.totalRecords});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final stages = (trends?['stages'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    Widget bar(Map<String, dynamic> s) {
      final count = (s['count'] ?? 0) as num;
      final avg = s['average_confidence'];
      final share =
          totalRecords > 0 ? (count / totalRecords).clamp(0.0, 1.0) : 0.0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Both halves can outgrow a phone-width card, so each gets to shrink
          // rather than pushing the Row past its 340px budget. The bar below
          // still carries the proportion when the meta line has to truncate.
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Text(stageName('${s['stage']}'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800, color: p.text)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '$count record${count == 1 ? '' : 's'}'
                '${avg is num && count > 0 ? ' · ${(avg * 100).toStringAsFixed(0)}% avg' : ''}',
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ),
          ]),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: share,
            minHeight: 6,
            backgroundColor: p.border,
            color: p.accent,
          ),
        ]),
      );
    }

    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeading(
          compact: true,
          title: 'Fermentation Trends',
          subtitle: 'Stage counts and confidence aggregated on the server.',
        ),
        if (trends == null)
          const EmptyNote('Trend data will appear once the backend responds.')
        else if (stages.isEmpty)
          const EmptyNote('No classifications yet, so there is nothing to trend.')
        else
          for (final s in stages) bar(s),
      ]),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  final double gap;
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 240, this.gap = 16});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final maxCols = children.isEmpty ? 1 : children.length;
      final cols = (box.maxWidth / minWidth).floor().clamp(1, maxCols);
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children.map((e) => SizedBox(width: w, child: e)).toList(),
      );
    });
  }
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(22)});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        boxShadow: const [BoxShadow(color: Color(0x0F1D3523), blurRadius: 22, offset: Offset(0, 5))],
      ),
      child: child,
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool compact;
  const SectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 14 : 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: compact ? 16 : 20, fontWeight: FontWeight.w800, color: compact ? p.text : Colors.white)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: compact ? p.muted : Colors.white70)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String caption;
  const StatCard({super.key, required this.label, required this.icon, required this.value, required this.caption});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded so a long label wraps instead of overflowing the card
              // when the grid packs several StatCards into a narrow column.
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: p.accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(height: 2),
          Text(caption, style: TextStyle(fontSize: 11, color: p.muted)),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = status == 'Classified'
        ? AppColors.green
        : status == 'Flagged'
            ? AppColors.red
            : AppColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(.16), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

class EmptyNote extends StatelessWidget {
  final String message;
  const EmptyNote(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 8),
      child: Center(
        child: Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.muted, height: 1.6)),
      ),
    );
  }
}

class RecordTile extends StatelessWidget {
  final Batch batch;
  final VoidCallback? onTap;
  const RecordTile({super.key, required this.batch, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10)),
              child: Icon(batch.status == 'Classified' ? Icons.task_alt : Icons.schedule, size: 20, color: p.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(batch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: p.text)),
                  Text(
                    '${batch.fileName.isEmpty ? 'Image unavailable' : batch.fileName} · ${fmtDate(batch.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(batch.status),
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.dashGold,
        foregroundColor: AppColors.forest,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Flexible(child: Text(label)),
      ]),
    );
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const DetailRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final v = (value == null || value!.trim().isEmpty) ? 'Not provided' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6, color: p.muted)),
          const SizedBox(height: 2),
          Text(v, style: TextStyle(fontSize: 13, color: p.text)),
        ],
      ),
    );
  }
}

Future<void> showDetailsDialog(BuildContext context, String title, List<DetailRow> rows) {
  final p = Pal.of(context);
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ]),
              Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows))),
            ],
          ),
        ),
      ),
    ),
  );
}

List<DetailRow> batchDetailRows(Batch b) => [
      DetailRow('Batch Name', b.name),
      DetailRow('Batch ID', b.id),
      DetailRow('Filename', b.fileName),
      DetailRow('Date Submitted', fmtDate(b.createdAt)),
      DetailRow('Classification', b.stageLabel),
      DetailRow('Status', b.status),
      DetailRow('Confidence', b.confidenceLabel),
      DetailRow('Batch Notes', b.notes),
      DetailRow('Quality Notes', b.qualityNotes),
    ];

/// Search + status filter + table. Used by the staff and admin batch pages.
class BatchBrowser extends StatefulWidget {
  final List<Batch> batches;
  final void Function(Batch) onView;
  const BatchBrowser({super.key, required this.batches, required this.onView});

  @override
  State<BatchBrowser> createState() => _BatchBrowserState();
}

class _BatchBrowserState extends State<BatchBrowser> {
  String _q = '';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = widget.batches.where((b) {
      final q = _q.toLowerCase();
      final matchQ = q.isEmpty || b.name.toLowerCase().contains(q) || b.id.toLowerCase().contains(q) || b.fileName.toLowerCase().contains(q);
      return matchQ && (_status == 'all' || b.status == _status);
    }).toList();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search batch name, ID, or file',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            DropdownButton<String>(
              value: _status,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Classified', child: Text('Classified')),
                DropdownMenuItem(value: 'Flagged', child: Text('Flagged')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'all'),
            ),
          ]),
          const SizedBox(height: 14),
          if (list.isEmpty)
            const EmptyNote('No batch records found.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.muted),
                columns: const [
                  DataColumn(label: Text('BATCH')),
                  DataColumn(label: Text('DATE')),
                  DataColumn(label: Text('CLASSIFICATION')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('ACTION')),
                ],
                rows: list
                    .map((b) => DataRow(cells: [
                          DataCell(Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              Text(b.fileName, style: TextStyle(fontSize: 10, color: p.muted)),
                            ],
                          )),
                          DataCell(Text(fmtDate(b.createdAt), style: const TextStyle(fontSize: 12))),
                          DataCell(Text(b.stageLabel, style: const TextStyle(fontSize: 12))),
                          DataCell(StatusBadge(b.status)),
                          DataCell(TextButton(onPressed: () => widget.onView(b), child: const Text('View'))),
                        ]))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
