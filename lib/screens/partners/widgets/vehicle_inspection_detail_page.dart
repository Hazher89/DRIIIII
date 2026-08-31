import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/partner/vehicle_inspection_checklist.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'vehicle_inspection_pdf_actions.dart';

/// Fullskjerm detaljvisning for én bilkontroll.
class VehicleInspectionDetailPage extends StatefulWidget {
  const VehicleInspectionDetailPage({
    super.key,
    required this.inspection,
    this.partner,
    this.canCloseFollowUp = false,
  });

  final PartnerVehicleInspection inspection;
  final Partner? partner;
  final bool canCloseFollowUp;

  static Future<void> open(
    BuildContext context, {
    required PartnerVehicleInspection inspection,
    Partner? partner,
    bool canCloseFollowUp = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => VehicleInspectionDetailPage(
          inspection: inspection,
          partner: partner,
          canCloseFollowUp: canCloseFollowUp,
        ),
      ),
    );
  }

  @override
  State<VehicleInspectionDetailPage> createState() =>
      _VehicleInspectionDetailPageState();
}

class _VehicleInspectionDetailPageState extends State<VehicleInspectionDetailPage> {
  late PartnerVehicleInspection _inspection = widget.inspection;
  final _df = DateFormat('dd.MM.yyyy');
  final _dtf = DateFormat('dd.MM.yyyy HH:mm');
  bool _closing = false;

  VehicleInspectionChecklistSummary get _summary =>
      VehicleInspectionChecklistSummary.fromInspection(_inspection);

  Future<void> _openPdf() async {
    await VehicleInspectionPdfActions.openPdf(
      context,
      inspection: _inspection,
      partner: widget.partner,
    );
  }

  Future<void> _closeFollowUp() async {
    final notesCtrl = TextEditingController();
    DateTime? nextDate = _inspection.nextInspectionAt;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Lukk oppfølging'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Beskriv hva som er gjort for å utbedre avvikene. '
                  'Dette stemples på kontrollen.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Tiltak / kommentar *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Neste bilkontroll (valgfritt)'),
                  subtitle: Text(
                    nextDate != null ? _df.format(nextDate!) : 'Ikke satt',
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDate ?? DateTime.now().add(const Duration(days: 90)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) setLocal(() => nextDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (notesCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Lukk med stempel'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _closing = true);
    try {
      final updated = await PartnerService.closeInspectionFollowUp(
        inspectionId: _inspection.id,
        actionNotes: notesCtrl.text.trim(),
        nextInspectionAt: nextDate,
      );
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _inspection = updated.copyWith(
          followUpClosedByName: profile?.fullName,
        );
        _closing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oppfølging lukket og stemplet')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunne ikke lukke: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      notesCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ins = _inspection;
    final summary = _summary;
    final hasAvvik = ins.hasDeviation || summary.avvikCount > 0;
    final statusColor = hasAvvik
        ? (ins.followUpOpen ? Colors.orange.shade800 : const Color(0xFFEA580C))
        : DriftProTheme.primaryGreen;
    final statusTitle = hasAvvik
        ? (ins.followUpOpen ? 'Avvik — venter oppfølging' : 'Avvik registrert')
        : 'OK — ingen avvik';
    final statusDetail = hasAvvik
        ? '${summary.avvikCount} punkt med avvik'
        : '${summary.okCount} punkter godkjent';

    return Scaffold(
      appBar: AppBar(
        title: Text(ins.vehicleLabel, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Åpne PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _openPdf,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _StatusBanner(
            color: statusColor,
            title: statusTitle,
            detail: statusDetail,
            icon: hasAvvik ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
          ),
          const SizedBox(height: 16),
          _InfoGrid(
            rows: [
              ('Kontrollør', ins.inspectedByName ?? 'Ukjent'),
              ('Stempling', _dtf.format(ins.inspectedAt.toLocal())),
              if (ins.nextInspectionAt != null)
                ('Neste kontroll', _df.format(ins.nextInspectionAt!)),
              if (ins.followUpDueAt != null)
                ('Oppfølgingsfrist', _df.format(ins.followUpDueAt!)),
            ],
          ),
          if ((ins.deviationNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Avvik — kommentar fra kontroll',
              icon: Icons.report_outlined,
              color: Colors.orange.shade800,
              child: Text(
                ins.deviationNotes!.trim(),
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ),
          ],
          if (ins.followUpAcknowledgedAt != null) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Oppfølging lukket',
              icon: Icons.verified_outlined,
              color: DriftProTheme.primaryGreen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dtf.format(ins.followUpAcknowledgedAt!.toLocal()),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if ((ins.followUpActionNotes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ins.followUpActionNotes!.trim(),
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                  ],
                  if (ins.followUpClosedByName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Stemplet av ${ins.followUpClosedByName}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _KpiRow(
            ok: summary.okCount,
            avvik: summary.avvikCount,
            ukjent: summary.notCheckedCount,
          ),
          if (summary.avvikItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChecklistSection(
              title: 'Må fikses — avvik',
              items: summary.avvikItems,
              accent: Colors.orange.shade800,
            ),
          ],
          if (summary.okItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChecklistSection(
              title: 'Godkjent',
              items: summary.okItems,
              accent: DriftProTheme.primaryGreen,
            ),
          ],
          if (summary.otherItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChecklistSection(
              title: 'Annet / notert',
              items: summary.otherItems,
              accent: Colors.blueGrey,
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Vis PDF-rapport'),
          ),
          if (widget.canCloseFollowUp && ins.followUpOpen) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _closing ? null : _closeFollowUp,
              icon: _closing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt_outlined),
              label: const Text('Lukk oppfølging med stempel'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.color,
    required this.title,
    required this.detail,
    required this.icon,
  });

  final Color color;
  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.9))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      rows[i].$1,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      rows[i].$2,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.ok, required this.avvik, required this.ukjent});

  final int ok;
  final int avvik;
  final int ukjent;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        chip('OK', ok, DriftProTheme.primaryGreen),
        const SizedBox(width: 8),
        chip('Avvik', avvik, Colors.orange.shade800),
        const SizedBox(width: 8),
        chip('Ukjent', ukjent, Colors.blueGrey),
      ],
    );
  }
}

class _ChecklistSection extends StatelessWidget {
  const _ChecklistSection({
    required this.title,
    required this.items,
    required this.accent,
  });

  final String title;
  final List<VehicleInspectionChecklistRow> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.isAvvik ? Icons.close_rounded : Icons.check_rounded,
                      size: 18,
                      color: item.isAvvik ? Colors.orange.shade800 : DriftProTheme.primaryGreen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (item.displayValue != item.statusLabel)
                            Text(
                              item.displayValue,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      item.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: item.isAvvik ? Colors.orange.shade800 : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
