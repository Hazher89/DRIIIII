import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Godkjenning av fri-forespørsler fra MAVI-sjåfører (intern partner-side).
class PartnerFriTab extends StatefulWidget {
  final Partner partner;
  final List<PartnerVehicle> vehicles;

  const PartnerFriTab({super.key, required this.partner, required this.vehicles});

  @override
  State<PartnerFriTab> createState() => _PartnerFriTabState();
}

class _PartnerFriTabState extends State<PartnerFriTab> {
  List<PartnerFriRequest> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PartnerService.fetchFriRequests(partnerId: widget.partner.id);
    if (mounted) {
      setState(() {
        _requests = list;
        _loading = false;
      });
    }
  }

  String _vehicleLabel(String? vehicleId) {
    if (vehicleId == null) return '—';
    for (final v in widget.vehicles) {
      if (v.id == vehicleId) return v.unitCode;
    }
    return vehicleId.substring(0, 8);
  }

  Future<void> _review(PartnerFriRequest req, bool approve) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Godkjenn fri' : 'Avslå fri'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Kommentar (valgfritt)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bekreft')),
        ],
      ),
    );
    if (ok != true) return;
    await PartnerService.reviewFriRequest(
      requestId: req.id,
      companyId: widget.partner.companyId,
      approve: approve,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    await _load();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

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

    int countBetween(DateTime start, DateTime end) => _requests
        .where((r) => !r.requestDate.isBefore(start) && r.requestDate.isBefore(end))
        .length;

    return {
      'Uke': countBetween(weekStart, weekEnd),
      'Mnd': countBetween(monthStart, monthEnd),
      'År': countBetween(yearStart, yearEnd),
      'Totalt': _requests.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ingen fri-forespørsler fra denne partneren ennå.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final counts = _friCounts();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _FriSummaryRow(counts: counts);
          }
          final r = _requests[i - 1];
          final df = DateFormat('d. MMM yyyy', 'nb');
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          df.format(r.requestDate),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        r.status,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _statusColor(r.status),
                        ),
                      ),
                    ],
                  ),
                  Text('MAVI: ${_vehicleLabel(r.partnerVehicleId)}', style: DriftProTheme.caption),
                  if (r.reason != null && r.reason!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(r.reason!),
                    ),
                  if (r.status == 'pending') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _review(r, false),
                            child: const Text('Avslå'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _review(r, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: DriftProTheme.primaryGreen,
                            ),
                            child: const Text('Godkjenn'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
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
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.22),
          ],
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
