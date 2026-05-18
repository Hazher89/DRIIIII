import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/brreg_service.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';

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
  final _portalUsernameCtrl = TextEditingController();
  final _portalLoginEmailCtrl = TextEditingController();
  final List<TextEditingController> _maviControllers = [
    TextEditingController(text: 'NO_O_M0001'),
  ];
  final List<TextEditingController> _regControllers = [TextEditingController()];

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
    _portalUsernameCtrl.dispose();
    _portalLoginEmailCtrl.dispose();
    for (final c in _regControllers) {
      c.dispose();
    }
    for (final c in _maviControllers) {
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
    });
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
      final linkEmail = _inviteEmailCtrl.text.trim().isNotEmpty
          ? _inviteEmailCtrl.text.trim()
          : _portalLoginEmailCtrl.text.trim();
      if (linkEmail.contains('@')) {
        await _tryLinkInvite(created.id, emailOverride: linkEmail);
      }
      await _upsertPortalAccount(created.id, cid);
      final portalEmail = _portalLoginEmailCtrl.text.trim();
      final portalUser = _portalUsernameCtrl.text.trim();
      if (portalUser.isNotEmpty && portalEmail.contains('@')) {
        try {
          await PartnerService.sendPartnerPortalMagicLink(email: portalEmail);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Innloggingslenke er sendt til $portalEmail. Be partneren åpne e-posten og følge lenken.',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Kunne ikke sende innloggingslenke (sjekk Supabase e-post / spam): $e')),
            );
          }
        }
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
    for (int i = 0; i < _maviControllers.length; i++) {
      final unit = MaviUnitCodes.normalize(_maviControllers[i].text);
      if (unit.isEmpty || seen.contains(unit)) continue;
      seen.add(unit);
      final regRaw = _regControllers[i].text.trim().toUpperCase();
      final reg = regRaw.isEmpty ? MaviUnitCodes.regNrPlaceholder : regRaw;
      vehicles.add(
        PartnerVehicle(
          id: '',
          partnerId: created.id,
          companyId: created.companyId,
          unitCode: unit,
          registrationNumber: reg,
          createdAt: DateTime.now(),
        ),
      );
    }
    await PartnerService.replaceVehicles(
      partnerId: created.id,
      companyId: created.companyId,
      vehicles: vehicles,
    );
  }

  Future<void> _upsertPortalAccount(String partnerId, String companyId) async {
    final username = _portalUsernameCtrl.text.trim();
    final loginEmail = _portalLoginEmailCtrl.text.trim();
    if (username.isEmpty || loginEmail.isEmpty) return;
    if (!loginEmail.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Portal innloggings-epost må være en gyldig e-postadresse.'),
          ),
        );
      }
      return;
    }
    await PartnerService.upsertPortalAccount(
      partnerId: partnerId,
      companyId: companyId,
      username: username,
      loginEmail: loginEmail,
    );
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
          Text(
            'MAVI-nummer (${_maviControllers.length}) — flere per bedrift',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Reg.nr kan fylles ut senere. MAVI er påkrevd for rutefordeling.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...List.generate(_maviControllers.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _maviControllers[i],
                      decoration: const InputDecoration(
                        labelText: 'MAVI-nummer',
                        hintText: 'NO_O_M0001',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _regControllers[i],
                      decoration: const InputDecoration(
                        labelText: 'Reg.nr (valgfritt)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _maviControllers[i].dispose();
                        _regControllers[i].dispose();
                        _maviControllers.removeAt(i);
                        _regControllers.removeAt(i);
                      });
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
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
                  label: const Text('Flere på en gang'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Partner-portal bruker', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Ingen passord lagres her. Når brukernavn og innloggings-e-post er fylt ut, sendes en sikker innloggingslenke (e-post). '
            'Partneren ser kun dokumenter, avtaler, oppsummering og ruter som er delt med dem (GDPR).',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _inviteEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-post til eksisterende MAVI-bruker (valgfritt, Google/Apple)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _portalUsernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Portal brukernavn (f.eks. m01_olsen)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _portalLoginEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Portal innloggings-e-post (mottar lenke)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Brukernavn kan brukes i stedet for e-post ved innlogging. Passord velger partneren via lenken i e-posten.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
