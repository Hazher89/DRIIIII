import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/utils/business_days.dart';
import '../../../core/utils/nb_date_format.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class DriverPortalFriPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const DriverPortalFriPage({super.key, required this.partner, required this.profile});

  @override
  State<DriverPortalFriPage> createState() => _DriverPortalFriPageState();
}

class _DriverPortalFriPageState extends State<DriverPortalFriPage> {
  List<PartnerFriRequest> _mine = [];
  bool _loading = true;

  Map<String, int> _friCounts() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(
      now.month == 12 ? now.year + 1 : now.year,
      now.month == 12 ? 1 : now.month + 1,
      1,
    );
    final yearStart = DateTime(now.year, 1, 1);
    final yearEnd = DateTime(now.year + 1, 1, 1);

    int countBetween(DateTime start, DateTime end) => _mine
        .where((r) => !r.requestDate.isBefore(start) && r.requestDate.isBefore(end))
        .length;

    return {
      'Uke': countBetween(weekStart, weekEnd),
      'Mnd': countBetween(monthStart, monthEnd),
      'År': countBetween(yearStart, yearEnd),
      'Totalt': _mine.length,
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await PartnerService.fetchFriRequests(partnerId: widget.partner.id);
    final vid = widget.profile.partnerVehicleId;
    if (mounted) {
      setState(() {
        _mine = vid == null ? all : all.where((r) => r.partnerVehicleId == vid).toList();
        _loading = false;
      });
    }
  }

  Future<void> _requestFri() async {
    final reasonCtrl = TextEditingController();
    final earliest = BusinessDays.earliestAllowedDate(minBusinessDays: 3);
    var date = earliest;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Søk fri'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Du må søke minst 3 virkedager i forveien (uten lørdag, søndag og helligdager). '
                'Tidligste dato: ${DateFormat('d. MMM yyyy', 'nb').format(earliest)}.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Første fri-dag'),
                subtitle: Text(NbDateFormat.format(date, 'EEEE d. MMM yyyy')),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date.isBefore(earliest) ? earliest : date,
                    firstDate: earliest,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    selectableDayPredicate: BusinessDays.isBusinessDay,
                  );
                  if (d != null) setLocal(() => date = d);
                },
              ),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Begrunnelse',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (date.isBefore(earliest) || !BusinessDays.isBusinessDay(date)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Velg en virkedag minst ${NbDateFormat.format(earliest, 'd.M.y')} (3 virkedager + helligdager).',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    await PartnerService.createFriRequest(
      companyId: widget.partner.companyId,
      partnerId: widget.partner.id,
      partnerVehicleId: widget.profile.partnerVehicleId,
      requestDate: date,
      reason: reason.isEmpty ? null : reason,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fri-forespørsel sendt. Venter godkjenning fra MAVI.')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return PartnerPortalPageShell(
      title: 'Fri',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _requestFri,
        icon: const Icon(Icons.add),
        label: const Text('Søk fri'),
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: _mine.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 80),
                        Text(
                          'Ingen fri-forespørsler ennå.',
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Dra ned for å oppdatere, eller trykk «Søk fri».',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _mine.length + 1,
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _FriSummaryRow(counts: _friCounts());
                        }
                        final r = _mine[i - 1];
                        Color c = Colors.orange;
                        if (r.status == 'approved') c = Colors.green;
                        if (r.status == 'rejected') c = Colors.red;
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            title: Text(
                              NbDateFormat.format(r.requestDate, 'd. MMM yyyy'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(r.reason ?? '—'),
                            trailing: Text(
                              r.status,
                              style: TextStyle(color: c, fontWeight: FontWeight.w800),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _FriSummaryRow extends StatelessWidget {
  final Map<String, int> counts;

  const _FriSummaryRow({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _FriSummaryChip(
          label: 'Uke',
          value: counts['Uke'] ?? 0,
          color: DriftProTheme.accentBlue,
        ),
        _FriSummaryChip(
          label: 'Mnd',
          value: counts['Mnd'] ?? 0,
          color: Colors.deepPurple.shade600,
        ),
        _FriSummaryChip(
          label: 'År',
          value: counts['År'] ?? 0,
          color: Colors.teal.shade700,
        ),
        _FriSummaryChip(
          label: 'Totalt',
          value: counts['Totalt'] ?? 0,
          color: Colors.grey.shade700,
        ),
      ],
    );
  }
}

class _FriSummaryChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _FriSummaryChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
