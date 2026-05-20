import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/brreg_service.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../core/utils/portal_credentials.dart';

class NewPartnerScreen extends StatefulWidget {
  const NewPartnerScreen({super.key});

  @override
  State<NewPartnerScreen> createState() => _NewPartnerScreenState();
}

class _NewPartnerScreenState extends State<NewPartnerScreen> {
  final _searchCtrl = TextEditingController();
  final _orgLookupCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _vehiclesCtrl = TextEditingController(text: '0');
  final _payloadCtrl = TextEditingController();
  final _inviteEmailCtrl = TextEditingController();
  final List<TextEditingController> _regOnlyControllers = [TextEditingController()];
  final List<TextEditingController> _maviControllers = [
    TextEditingController(text: 'NO_O_M0001'),
  ];
  final List<TextEditingController> _regControllers = [TextEditingController()];
  final List<TextEditingController> _driverNameControllers = [TextEditingController()];
  final List<TextEditingController> _driverPhoneControllers = [TextEditingController()];

  bool _euApproved = false;
  bool _searching = false;
  bool _saving = false;
  List<BrregCompanyHit> _hits = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _orgLookupCtrl.dispose();
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _postalCtrl.dispose();
    _cityCtrl.dispose();
    _notesCtrl.dispose();
    _vehiclesCtrl.dispose();
    _payloadCtrl.dispose();
    _inviteEmailCtrl.dispose();
    for (final c in _regOnlyControllers) {
      c.dispose();
    }
    for (final c in _regControllers) {
      c.dispose();
    }
    for (final c in _maviControllers) {
      c.dispose();
    }
    for (final c in _driverNameControllers) {
      c.dispose();
    }
    for (final c in _driverPhoneControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _existingMavi => _maviControllers
      .map((c) => MaviUnitCodes.normalize(c.text))
      .where((s) => s.isNotEmpty)
      .toList();

  void _addMaviRow() {
    setState(() {
      _maviControllers.add(TextEditingController(text: MaviUnitCodes.suggestNext(_existingMavi)));
      _regControllers.add(TextEditingController());
      _driverNameControllers.add(TextEditingController());
      _driverPhoneControllers.add(TextEditingController());
    });
  }

  void _addRegOnlyRow() {
    setState(() => _regOnlyControllers.add(TextEditingController()));
  }

  Future<void> _bulkAddMavi() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legg til flere MAVI-nummer'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'M0001\nM0002\nNO_O_M0003',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Legg til')),
        ],
      ),
    );
    if (ok != true) return;
    final codes = MaviUnitCodes.parseBulk(ctrl.text);
    final seen = _existingMavi.toSet();
    setState(() {
      for (final code in codes) {
        if (seen.contains(code)) continue;
        seen.add(code);
        _maviControllers.add(TextEditingController(text: code));
        _regControllers.add(TextEditingController());
        _driverNameControllers.add(TextEditingController());
        _driverPhoneControllers.add(TextEditingController());
      }
    });
  }

  Future<void> _runBrregNameSearch() async {
    setState(() => _searching = true);
    try {
      final hits = await BrregService.searchByName(_searchCtrl.text);
      setState(() => _hits = hits);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _applyHit(BrregCompanyHit h) {
    _orgLookupCtrl.text = h.orgNumber;
    _nameCtrl.text = h.name;
    _cityCtrl.text = h.city ?? _cityCtrl.text;
    setState(() => _hits = []);
  }

  Future<void> _runOrgLookup() async {
    setState(() => _searching = true);
    try {
      final d = await BrregService.fetchByOrgNumber(_orgLookupCtrl.text);
      if (d == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fant ingen enhet.')));
        return;
      }
      setState(() {
        _nameCtrl.text = d.name;
        _orgLookupCtrl.text = d.orgNumber;
        _ownerCtrl.text = d.dailyLeaderName ?? _ownerCtrl.text;
        _phoneCtrl.text = d.phone ?? _phoneCtrl.text;
        _emailCtrl.text = d.email ?? _emailCtrl.text;
        _addressCtrl.text = d.street ?? _addressCtrl.text;
        _postalCtrl.text = d.postalCode ?? _postalCtrl.text;
        _cityCtrl.text = d.city ?? _cityCtrl.text;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bedriftsnavn er påkrevd')));
      return;
    }
    setState(() => _saving = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Mangler company_id');
      final orgTrim = _orgLookupCtrl.text.replaceAll(RegExp(r'\s'), '');
      final veh = int.tryParse(_vehiclesCtrl.text) ?? 0;
      final pay = int.tryParse(_payloadCtrl.text);

      final snapshot = _orgLookupCtrl.text.isNotEmpty
          ? (await BrregService.fetchByOrgNumber(orgTrim))?.raw
          : null;

      final p = Partner(
        id: '',
        companyId: cid,
        orgNumber: orgTrim.isEmpty ? null : orgTrim,
        name: _nameCtrl.text.trim(),
        ownerName: _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        postalCode: _postalCtrl.text.trim().isEmpty ? null : _postalCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        country: 'NO',
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        vehicleCountRegistered: veh,
        vehicleMaxPayloadKg: pay,
        euApproved: _euApproved ? true : null,
        brregSnapshot: snapshot,
        createdAt: DateTime.now(),
      );

      final created = await PartnerService.createPartner(p);
      await _saveVehicles(created);
      final linkEmail = _inviteEmailCtrl.text.trim();
      if (linkEmail.contains('@')) {
        await _tryLinkInvite(created.id, emailOverride: linkEmail);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveVehicles(Partner created) async {
    final vehicles = <PartnerVehicle>[];
    final seen = <String>{};

    for (final c in _regOnlyControllers) {
      final regRaw = c.text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
      if (regRaw.length < 4) continue;
      final unit = MaviUnitCodes.registrationUnitCode(regRaw);
      if (unit.isEmpty || seen.contains(unit)) continue;
      seen.add(unit);
      vehicles.add(
        PartnerVehicle(
          id: '',
          partnerId: created.id,
          companyId: created.companyId,
          unitCode: unit,
          registrationNumber: regRaw,
          vehicleKind: 'registration',
          createdAt: DateTime.now(),
        ),
      );
    }

    for (int i = 0; i < _maviControllers.length; i++) {
      final unit = MaviUnitCodes.normalize(_maviControllers[i].text);
      if (unit.isEmpty || seen.contains(unit)) continue;
      seen.add(unit);
      final regRaw = _regControllers[i].text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
      final reg = regRaw.isEmpty ? MaviUnitCodes.regNrPlaceholder : regRaw;
      final driverName = _driverNameControllers[i].text.trim();
      final phone = _driverPhoneControllers[i].text.trim();
      vehicles.add(
        PartnerVehicle(
          id: '',
          partnerId: created.id,
          companyId: created.companyId,
          unitCode: unit,
          registrationNumber: reg,
          vehicleKind: 'mavi',
          driverName: driverName.isEmpty ? null : driverName,
          phone: phone.isEmpty ? null : phone,
          createdAt: DateTime.now(),
        ),
      );
    }

    final saved = await PartnerService.replaceVehicles(
      partnerId: created.id,
      companyId: created.companyId,
      vehicles: vehicles,
    );

    for (int i = 0; i < _maviControllers.length; i++) {
      final unit = MaviUnitCodes.normalize(_maviControllers[i].text);
      final phone = _driverPhoneControllers[i].text.trim();
      final driverName = _driverNameControllers[i].text.trim();
      if (unit.isEmpty || phone.length < 8 || driverName.isEmpty) continue;
      PartnerVehicle? vehicle;
      for (final v in saved) {
        if (v.unitCode == unit) {
          vehicle = v;
          break;
        }
      }
      if (vehicle == null) continue;
      try {
        await PartnerService.provisionDriverPortal(
          partnerId: created.id,
          companyId: created.companyId,
          partnerVehicleId: vehicle.id,
          unitCode: unit,
          phone: phone,
          driverName: driverName,
        );
      } catch (e) {
        debugPrint('provisionDriverPortal $unit: $e');
      }
    }
  }

  Future<void> _tryLinkInvite(String partnerId, {String? emailOverride}) async {
    final email = (emailOverride ?? _inviteEmailCtrl.text.trim()).trim();
    if (email.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      if (row == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ingen profil med denne e-posten ennå. Opprett bruker i Supabase Auth og knytt partner_id manuelt, eller be brukeren registrere seg.',
              ),
            ),
          );
        }
        return;
      }
      await PartnerService.linkProfileToPartner(
        profileId: row['id'] as String,
        partnerId: partnerId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bruker er knyttet til partner (portal-aktivert).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke knytte bruker (sjekk RLS/tilgang): $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ny samarbeidspartner')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Brønnøysund (Brreg)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Søk bedriftsnavn',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _runBrregNameSearch(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _searching ? null : _runBrregNameSearch,
                icon: _searching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
              ),
            ],
          ),
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._hits.map(
              (h) => ListTile(
                dense: true,
                title: Text(h.name),
                subtitle: Text('${h.orgNumber} ${h.city ?? ''}'),
                onTap: () => _applyHit(h),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orgLookupCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Org.nr (9 siffer) — hent data',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _runOrgLookup,
                child: const Text('Hent'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Bedrift', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Navn *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ownerCtrl,
            decoration: const InputDecoration(
              labelText: 'Daglig leder / kontaktperson (eier)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'E-post', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(labelText: 'Adresse', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _postalCtrl,
                  decoration: const InputDecoration(labelText: 'Postnr', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(labelText: 'Sted', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Kjøretøy & samsvar', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vehiclesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ant. registrerte vogntog/lastebiler (bedrift)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _payloadCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nyttelast kg (typisk)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            value: _euApproved,
            onChanged: (v) => setState(() => _euApproved = v),
            title: const Text('EU-godkjent materiell (oppgitt)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notater', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Registrerte biler (reg.nr)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Flere registreringsnummer for bedriften — uavhengig av MAVI.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...List.generate(_regOnlyControllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _regOnlyControllers[i],
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Registreringsnummer',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _regOnlyControllers[i].dispose();
                        _regOnlyControllers.removeAt(i);
                      });
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: _addRegOnlyRow,
            icon: const Icon(Icons.directions_car_outlined),
            label: const Text('Legg til reg.nr'),
          ),
          const SizedBox(height: 20),
          Text(
            'MAVI & sjåfør (${_maviControllers.length})',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Brukernavn genereres automatisk. Fyll navn + telefon — ved lagring opprettes sjåfør og SMS sendes.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...List.generate(_maviControllers.length, (i) {
            final unit = MaviUnitCodes.normalize(_maviControllers[i].text);
            final userPreview = unit.isEmpty ? '' : PortalCredentials.driverUsername(unit);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _maviControllers[i],
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'MAVI-nummer *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _maviControllers[i].dispose();
                                _regControllers[i].dispose();
                                _driverNameControllers[i].dispose();
                                _driverPhoneControllers[i].dispose();
                                _maviControllers.removeAt(i);
                                _regControllers.removeAt(i);
                                _driverNameControllers.removeAt(i);
                                _driverPhoneControllers.removeAt(i);
                              });
                            },
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _driverNameControllers[i],
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Sjåfør navn (personnavn)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _driverPhoneControllers[i],
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Sjåfør telefon (SMS med innlogging)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (userPreview.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Auto brukernavn: $userPreview · passord sendes på SMS',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addMaviRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Legg til MAVI'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _bulkAddMavi,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Flere MAVI'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Eksisterende bruker (valgfritt)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _inviteEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-post til eksisterende intern bruker',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Lagre samarbeidspartner'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
