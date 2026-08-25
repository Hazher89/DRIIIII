import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/portal_credentials.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';

class OwnerPortalStaffPage extends StatefulWidget {
  final Partner partner;

  const OwnerPortalStaffPage({super.key, required this.partner});

  @override
  State<OwnerPortalStaffPage> createState() => _OwnerPortalStaffPageState();
}

class _OwnerPortalStaffPageState extends State<OwnerPortalStaffPage> {
  List<PartnerStaff> _staff = [];
  bool _loading = true;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final enabled =
          await PartnerWorkforceService.isEnabled(widget.partner.id);
      final list = enabled
          ? await PartnerWorkforceService.listStaff(
              partnerId: widget.partner.id,
              includeInactive: true,
            )
          : <PartnerStaff>[];
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _staff = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addStaff() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final postal = TextEditingController();
    final city = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny ansatt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Fullt navn *')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Telefon *'), keyboardType: TextInputType.phone),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Adresse')),
              TextField(controller: postal, decoration: const InputDecoration(labelText: 'Postnr')),
              TextField(controller: city, decoration: const InputDecoration(labelText: 'Sted')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final me = await SupabaseService.fetchEffectiveUserProfile();
    await PartnerWorkforceService.createStaff(
      partnerId: widget.partner.id,
      companyId: widget.partner.companyId,
      fullName: name.text,
      phone: phone.text,
      address: address.text,
      postalCode: postal.text,
      city: city.text,
      createdBy: me?.id,
    );
    await _load();
  }

  Future<void> _provision(PartnerStaff s) async {
    try {
      final res = await PartnerWorkforceService.provisionStaffLogin(
        staff: s,
        partnerName: widget.partner.name,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Innlogging opprettet'),
          content: SelectableText(
            PortalCredentials.displayLoginHint(
              username: res.username,
              password: res.password,
              isOwner: false,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                  text: 'Brukernavn: ${res.username}\nPassord: ${res.password}',
                ));
              },
              child: const Text('Kopier'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PartnerPortalPageShell(
      title: 'Ansatte',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          tooltip: 'Logg ut',
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      floatingActionButton: _enabled
          ? FloatingActionButton.extended(
              onPressed: _addStaff,
              icon: const Icon(Icons.person_add),
              label: const Text('Ny ansatt'),
            )
          : null,
      body: _loading
          ? const DriftProLoadingCenter()
          : !_enabled
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Stempling / ansatte er ikke aktivert for din bedrift.\n'
                      'Kontakt DriftPro-superadmin for å slå på funksjonen.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _staff.length,
                        itemBuilder: (_, i) {
                          final s = _staff[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                                child: Text(
                                  s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              title: Text(s.fullName),
                              subtitle: Text(
                                [
                                  if (s.phone != null) s.phone!,
                                  if (s.addressLine.isNotEmpty) s.addressLine,
                                  if (!s.isActive) 'Deaktivert',
                                  if (s.profileId != null) 'Har innlogging',
                                ].join(' · '),
                              ),
                              trailing: s.profileId == null && s.isActive
                                  ? TextButton(
                                      onPressed: () => _provision(s),
                                      child: const Text('Lag bruker'),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
