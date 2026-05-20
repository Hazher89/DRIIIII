import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';

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
    var date = DateTime.now().add(const Duration(days: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Søk fri'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Dato'),
                subtitle: Text(DateFormat('d. MMM yyyy', 'nb').format(date)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fri'),
        actions: [
          IconButton(tooltip: 'Søk fri', onPressed: _requestFri, icon: const Icon(Icons.add)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => signOutFromPortal(context)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mine.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Ingen fri-forespørsler ennå.', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _requestFri,
                          icon: const Icon(Icons.beach_access),
                          label: const Text('Søk fri'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _mine.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _mine[i];
                      Color c = Colors.orange;
                      if (r.status == 'approved') c = Colors.green;
                      if (r.status == 'rejected') c = Colors.red;
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          title: Text(
                            DateFormat('d. MMM yyyy', 'nb').format(r.requestDate),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(r.reason ?? '—'),
                          trailing: Text(r.status, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
