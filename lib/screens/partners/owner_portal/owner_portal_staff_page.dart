import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/services/sms/sms_phone_utils.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/portal_credentials.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';

class OwnerPortalStaffPage extends StatefulWidget {
  final Partner partner;

  const OwnerPortalStaffPage({super.key, required this.partner});

  @override
  State<OwnerPortalStaffPage> createState() => _OwnerPortalStaffPageState();
}

class _OwnerPortalStaffPageState extends State<OwnerPortalStaffPage> {
  List<PartnerStaff> _staff = [];
  List<PartnerVehicle> _vehicles = [];
  Map<String, PartnerPortalAccount> _accountsById = {};
  bool _loading = true;
  bool _enabled = false;
  String? _error;
  String _query = '';
  bool _showInactive = true;

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
      if (!enabled) {
        if (!mounted) return;
        setState(() {
          _enabled = false;
          _staff = [];
          _loading = false;
        });
        return;
      }
      final list = await PartnerWorkforceService.listStaff(
        partnerId: widget.partner.id,
        includeInactive: true,
      );
      final vehicles = await PartnerService.fetchVehicles(widget.partner.id);
      final accounts =
          await PartnerService.fetchPortalAccounts(widget.partner.id);
      final byId = <String, PartnerPortalAccount>{};
      for (final a in accounts) {
        if (a.accountKind == 'staff') byId[a.id] = a;
      }
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _staff = list;
        _vehicles = vehicles.where((v) => v.isActive).toList();
        _accountsById = byId;
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

  List<PartnerStaff> get _filtered {
    final q = _query.trim().toLowerCase();
    return _staff.where((s) {
      if (!_showInactive && !s.isActive) return false;
      if (q.isEmpty) return true;
      final username = _usernameFor(s)?.toLowerCase() ?? '';
      return s.fullName.toLowerCase().contains(q) ||
          (s.phone?.contains(q) ?? false) ||
          s.addressLine.toLowerCase().contains(q) ||
          username.contains(q);
    }).toList();
  }

  String? _usernameFor(PartnerStaff s) {
    if (s.portalAccountId != null) {
      return _accountsById[s.portalAccountId!]?.username;
    }
    for (final a in _accountsById.values) {
      if (s.profileId != null && a.profileId == s.profileId) return a.username;
    }
    return null;
  }

  Future<void> _showCredentialsDialog({
    required String title,
    required PartnerStaff s,
    required String username,
    required String password,
  }) async {
    final share = PortalCredentials.shareCredentialsMessage(
      fullName: s.fullName,
      username: username,
      password: password,
      partnerName: widget.partner.name,
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kun for ${s.fullName} · ${widget.partner.name}\n'
                'Logg inn via «Samarbeidspartner» (ikke MAVI ansatte).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Brukernavn: $username\nPassord: $password',
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: username));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Brukernavn kopiert')),
              );
            },
            child: const Text('Kopier bruker'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: password));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Passord kopiert')),
              );
            },
            child: const Text('Kopier passord'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: share));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hele meldingen kopiert')),
              );
            },
            child: const Text('Kopier alt'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
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
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Fullt navn *'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(
                  labelText: 'Telefon *',
                  hintText: '45045411',
                  helperText: '8 siffer, start med 4 eller 9',
                ),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              TextField(
                controller: postal,
                decoration: const InputDecoration(labelText: 'Postnr'),
              ),
              TextField(
                controller: city,
                decoration: const InputDecoration(labelText: 'Sted'),
              ),
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
    if (!isValidNorwegianMobile(phone.text)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ugyldig mobil — 8 siffer, start med 4 eller 9'),
          backgroundColor: DriftProTheme.error,
        ),
      );
      return;
    }
    final me = await SupabaseService.fetchEffectiveUserProfile();
    await PartnerWorkforceService.createStaff(
      partnerId: widget.partner.id,
      companyId: widget.partner.companyId,
      fullName: name.text,
      phone: displayPhoneNo(normalizePhoneNo(phone.text)!),
      address: address.text,
      postalCode: postal.text,
      city: city.text,
      createdBy: me?.id,
    );
    await _load();
  }

  Future<void> _provision(PartnerStaff s) async {
    if (!isValidNorwegianMobile(s.phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sett gyldig mobil først (Endre telefon)'),
          backgroundColor: DriftProTheme.error,
        ),
      );
      return;
    }
    try {
      final res = await PartnerWorkforceService.provisionStaffLogin(
        staff: s,
        partnerName: widget.partner.name,
      );
      if (!mounted) return;
      await _showCredentialsDialog(
        title: 'Innlogging opprettet',
        s: s,
        username: res.username,
        password: res.password,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _resetPassword(PartnerStaff s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nytt passord?'),
        content: Text(
          'Lager nytt passord for «${s.fullName}». '
          'Det gamle slutter å virke med én gang. '
          'Du får det nye passordet her for å sende til den ansatte.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lag nytt passord')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await PartnerWorkforceService.resetStaffPassword(
        staff: s,
        partnerName: widget.partner.name,
      );
      if (!mounted) return;
      await _showCredentialsDialog(
        title: 'Nytt passord klart',
        s: s,
        username: res.username,
        password: res.password,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
      );
    }
  }

  Future<void> _editDetails(PartnerStaff s) async {
    final name = TextEditingController(text: s.fullName);
    final phone = TextEditingController(text: s.phone ?? '');
    final address = TextEditingController(text: s.address ?? '');
    final postal = TextEditingController(text: s.postalCode ?? '');
    final city = TextEditingController(text: s.city ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger ansatt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Navn')),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Telefon'),
                keyboardType: TextInputType.phone,
              ),
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
    if (ok != true) {
      name.dispose();
      phone.dispose();
      address.dispose();
      postal.dispose();
      city.dispose();
      return;
    }
    if (phone.text.trim().isNotEmpty && !isValidNorwegianMobile(phone.text)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ugyldig mobil'),
          backgroundColor: DriftProTheme.error,
        ),
      );
      return;
    }
    try {
      await PartnerWorkforceService.updateStaff(
        s.copyWith(
          fullName: name.text.trim(),
          phone: phone.text.trim().isEmpty
              ? s.phone
              : displayPhoneNo(normalizePhoneNo(phone.text)!),
          address: address.text,
          postalCode: postal.text,
          city: city.text,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      name.dispose();
      phone.dispose();
      address.dispose();
      postal.dispose();
      city.dispose();
    }
  }

  Future<void> _toggleRoutes(PartnerStaff s, bool enabled) async {
    if (!enabled) {
      try {
        await PartnerWorkforceService.setRouteAccess(
          staffId: s.id,
          enabled: false,
        );
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
      return;
    }

    final picked = await _pickRouteVehicles(
      title: 'Velg biler for ${s.fullName}',
      initialSelected: s.routeVehicleIds.toSet(),
    );
    if (picked == null) return;

    try {
      await PartnerWorkforceService.setRouteAccess(
        staffId: s.id,
        enabled: true,
        vehicleIds: picked.toList(),
      );
      await _load();
      if (!mounted) return;
      if (picked.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Rutetilgang aktivert uten biler — velg biler for at ansatt skal se ruter.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
      );
    }
  }

  Future<void> _editRouteVehicles(PartnerStaff s) async {
    final picked = await _pickRouteVehicles(
      title: 'Biler for ${s.fullName}',
      initialSelected: s.routeVehicleIds.toSet(),
    );
    if (picked == null) return;
    try {
      await PartnerWorkforceService.setRouteVehicles(
        staffId: s.id,
        vehicleIds: picked.toList(),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            picked.isEmpty
                ? 'Ingen biler valgt — ansatt ser ingen ruter før du velger bil.'
                : 'Oppdatert: ${picked.length} bil${picked.length == 1 ? '' : 'er'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
      );
    }
  }

  Future<Set<String>?> _pickRouteVehicles({
    required String title,
    required Set<String> initialSelected,
  }) async {
    if (_vehicles.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingen aktive MAVI-biler registrert på bedriften ennå.'),
        ),
      );
      return null;
    }

    final selected = Set<String>.from(initialSelected);

    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(
                      'Velg én eller flere biler ansatt kan motta og godkjenne ruter for.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final v in _vehicles)
                            CheckboxListTile(
                              value: selected.contains(v.id),
                              onChanged: (on) {
                                setLocal(() {
                                  if (on == true) {
                                    selected.add(v.id);
                                  } else {
                                    selected.remove(v.id);
                                  }
                                });
                              },
                              title: Text(
                                MaviUnitCodes.normalize(v.unitCode),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(v.registrationNumber),
                              secondary: const Icon(Icons.local_shipping_outlined),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setLocal(() => selected.clear()),
                          child: const Text('Ingen biler'),
                        ),
                        TextButton(
                          onPressed: () => setLocal(() {
                            selected
                              ..clear()
                              ..addAll(_vehicles.map((v) => v.id));
                          }),
                          child: const Text('Alle biler'),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, Set<String>.from(selected)),
                      child: Text(
                        selected.isEmpty
                            ? 'Lagre uten biler'
                            : 'Lagre (${selected.length} bil${selected.length == 1 ? '' : 'er'})',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _setActive(PartnerStaff s, bool active) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? 'Aktiver ansatt?' : 'Deaktiver ansatt?'),
        content: Text(
          active
              ? '«${s.fullName}» kan stemple og logge inn igjen.'
              : '«${s.fullName}» mister stempling og innlogging. Timer beholdes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(active ? 'Aktiver' : 'Deaktiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PartnerWorkforceService.setStaffActive(staffId: s.id, active: active);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
      );
    }
  }

  Future<void> _hardDelete(PartnerStaff s) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Slett permanent?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '«${s.fullName}» og alle timer slettes. Skriv SLETT for å bekrefte.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'SLETT',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setSt(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
              onPressed: ctrl.text.trim().toUpperCase() == 'SLETT'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Slett'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (ok != true) return;
    try {
      await PartnerWorkforceService.hardDeleteStaff(s.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    final active = _staff.where((s) => s.isActive).length;
    final withLogin = _staff.where((s) => s.profileId != null).length;
    final withRoutes = _staff.where((s) => s.canManageRoutes).length;
    final list = _filtered;

    return PartnerPortalPageShell(
      title: 'Ansatte',
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
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SizedBox(height: 80),
                      Text(
                        'Stempling / ansatte er ikke aktivert.\n'
                        'Kontakt DriftPro-superadmin.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : _error != null
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: 80),
                          Center(child: Text(_error!)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                        children: [
                          Row(
                            children: [
                              _OverviewChip(
                                label: 'Totalt',
                                value: '${_staff.length}',
                                color: Colors.blueGrey,
                              ),
                              const SizedBox(width: 8),
                              _OverviewChip(
                                label: 'Aktive',
                                value: '$active',
                                color: DriftProTheme.primaryGreen,
                              ),
                              const SizedBox(width: 8),
                              _OverviewChip(
                                label: 'Innlogging',
                                value: '$withLogin',
                                color: const Color(0xFF1565C0),
                              ),
                              const SizedBox(width: 8),
                              _OverviewChip(
                                label: 'Ruter',
                                value: '$withRoutes',
                                color: Colors.deepOrange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Søk navn, telefon, brukernavn…',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Vis deaktiverte'),
                            value: _showInactive,
                            onChanged: (v) => setState(() => _showInactive = v),
                          ),
                          if (list.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  _staff.isEmpty
                                      ? 'Ingen ansatte ennå — trykk «Ny ansatt»'
                                      : 'Ingen treff',
                                  style: TextStyle(color: muted),
                                ),
                              ),
                            )
                          else
                            ...list.map((s) {
                              final username = _usernameFor(s);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _StaffCard(
                                  staff: s,
                                  username: username,
                                  vehicles: _vehicles,
                                  onProvision: () => _provision(s),
                                  onResetPassword: () => _resetPassword(s),
                                  onEdit: () => _editDetails(s),
                                  onToggleRoutes: (v) => _toggleRoutes(s, v),
                                  onEditRouteVehicles: () => _editRouteVehicles(s),
                                  onActivate: () => _setActive(s, true),
                                  onDeactivate: () => _setActive(s, false),
                                  onDelete: () => _hardDelete(s),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: PartnerUi.mutedText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.staff,
    required this.username,
    required this.vehicles,
    required this.onProvision,
    required this.onResetPassword,
    required this.onEdit,
    required this.onToggleRoutes,
    required this.onEditRouteVehicles,
    required this.onActivate,
    required this.onDeactivate,
    required this.onDelete,
  });

  final PartnerStaff staff;
  final String? username;
  final List<PartnerVehicle> vehicles;
  final VoidCallback onProvision;
  final VoidCallback onResetPassword;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleRoutes;
  final VoidCallback onEditRouteVehicles;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onDelete;

  String _vehicleLabel(String id) {
    for (final v in vehicles) {
      if (v.id == id) {
        return '${MaviUnitCodes.normalize(v.unitCode)} · ${v.registrationNumber}';
      }
    }
    return id.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    final s = staff;
    final hasLogin = s.profileId != null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.isActive
              ? Colors.black.withValues(alpha: 0.06)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: s.isActive
                      ? DriftProTheme.primaryGreen.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Text(
                    s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: s.isActive
                          ? DriftProTheme.primaryGreen
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          decoration:
                              s.isActive ? null : TextDecoration.lineThrough,
                          color: s.isActive ? null : Colors.grey.shade700,
                        ),
                      ),
                      if (s.phone != null)
                        Text(s.phone!, style: TextStyle(fontSize: 13, color: muted)),
                      if (s.addressLine.isNotEmpty)
                        Text(
                          s.addressLine,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      if (username != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Bruker: $username',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Tag(
                            label: s.isActive ? 'Aktiv' : 'Deaktivert',
                            color: s.isActive
                                ? DriftProTheme.primaryGreen
                                : Colors.grey,
                          ),
                          _Tag(
                            label: hasLogin ? 'Har innlogging' : 'Mangler bruker',
                            color: hasLogin
                                ? const Color(0xFF1565C0)
                                : Colors.orange.shade800,
                          ),
                          if (s.canManageRoutes)
                            const _Tag(
                              label: 'Rutetilgang',
                              color: Colors.deepOrange,
                            ),
                          if (s.canManageRoutes && s.routeVehicleIds.isEmpty)
                            _Tag(
                              label: 'Ingen bil valgt',
                              color: Colors.red.shade700,
                            ),
                          if (s.canManageRoutes && s.routeVehicleIds.isNotEmpty)
                            _Tag(
                              label: '${s.routeVehicleIds.length} bil${s.routeVehicleIds.length == 1 ? '' : 'er'}',
                              color: const Color(0xFF1565C0),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        onEdit();
                      case 'provision':
                        onProvision();
                      case 'password':
                        onResetPassword();
                      case 'activate':
                        onActivate();
                      case 'deactivate':
                        onDeactivate();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Rediger')),
                    if (!hasLogin && s.isActive)
                      const PopupMenuItem(
                        value: 'provision',
                        child: Text('Lag bruker'),
                      ),
                    if (hasLogin)
                      const PopupMenuItem(
                        value: 'password',
                        child: Text('Nytt passord'),
                      ),
                    if (s.isActive)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Text('Deaktiver'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'activate',
                        child: Text('Aktiver'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Slett permanent',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (s.isActive) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  if (!hasLogin)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onProvision,
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Lag bruker + passord'),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onResetPassword,
                        icon: const Icon(Icons.lock_reset, size: 18),
                        label: const Text('Lag nytt passord'),
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text('Rutetilgang'),
                    subtitle: const Text(
                      'Velg hvilke MAVI-biler ansatt kan motta, se og godkjenne ruter for',
                    ),
                    value: s.canManageRoutes,
                    onChanged: hasLogin ? onToggleRoutes : null,
                  ),
                  if (s.canManageRoutes) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onEditRouteVehicles,
                          icon: const Icon(Icons.local_shipping_outlined, size: 18),
                          label: Text(
                            s.routeVehicleIds.isEmpty
                                ? 'Velg biler'
                                : 'Endre biler (${s.routeVehicleIds.length})',
                          ),
                        ),
                      ),
                    ),
                    if (s.routeVehicleIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final vid in s.routeVehicleIds)
                              Chip(
                                label: Text(
                                  _vehicleLabel(vid),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
