import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_timesheet_page.dart';

/// Kompakt timerbank-sammendrag på bil-eier oversikten.
class OwnerWorkforceSummaryCard extends StatefulWidget {
  const OwnerWorkforceSummaryCard({
    super.key,
    required this.partner,
    this.onTap,
  });

  final Partner partner;
  final VoidCallback? onTap;

  @override
  State<OwnerWorkforceSummaryCard> createState() => _OwnerWorkforceSummaryCardState();
}

class _OwnerWorkforceSummaryCardState extends State<OwnerWorkforceSummaryCard> {
  bool _loading = true;
  double _monthHours = 0;
  int _onJob = 0;
  int _staffCount = 0;
  int _entriesThisMonth = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final results = await Future.wait([
        PartnerWorkforceService.listStaff(partnerId: widget.partner.id),
        PartnerWorkforceService.listEntries(
          partnerId: widget.partner.id,
          from: from,
          to: now.add(const Duration(days: 1)),
        ),
      ]);
      final staff = results[0] as List<PartnerStaff>;
      final entries = results[1] as List<PartnerTimeEntry>;
      if (!mounted) return;
      setState(() {
        _staffCount = staff.length;
        _monthHours = PartnerWorkforceService.totalHours(entries);
        _onJob = PartnerWorkforceService.openStaffIds(entries).length;
        _entriesThisMonth = entries.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTimesheet() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OwnerPortalTimesheetPage(partner: widget.partner),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    final monthLabel = DateFormat('MMMM yyyy', 'nb').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _loading ? null : _openTimesheet,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: DriftProTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Timeliste & timerbank',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          Text(
                            'Ansattes timer · $monthLabel',
                            style: TextStyle(fontSize: 12.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: muted),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                else ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _MiniStat(
                        label: 'Timer mnd',
                        value: _monthHours.toStringAsFixed(1),
                        accent: DriftProTheme.primaryGreen,
                      ),
                      const SizedBox(width: 8),
                      _MiniStat(
                        label: 'På jobb nå',
                        value: '$_onJob',
                        accent: _onJob > 0 ? Colors.orange.shade800 : Colors.blueGrey,
                      ),
                      const SizedBox(width: 8),
                      _MiniStat(
                        label: 'Ansatte',
                        value: '$_staffCount',
                        accent: const Color(0xFF1565C0),
                      ),
                    ],
                  ),
                  if (_entriesThisMonth > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$_entriesThisMonth registreringer denne måneden — trykk for full oversikt',
                      style: TextStyle(fontSize: 12, color: muted, height: 1.35),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: accent),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: PartnerUi.mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
}
