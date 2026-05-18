import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _requests[i];
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
