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
import 'widgets/partner_companies_ui.dart';
import 'widgets/partner_ui.dart';

class NewPartnerScreen extends StatefulWidget {
  const NewPartnerScreen({super.key});

  @override
  State<NewPartnerScreen> createState() => _NewPartnerScreenState();
}

class _NewPartnerScreenState extends State<NewPartnerScreen> {
  final _orgLookupCtrl = TextEditingController();
  int _step = 0;
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
  bool _saving = false;

  @override
  void dispose() {
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
    final codes = await PartnerCompaniesUi.showMaviBulkPasteDialog(context);
    if (codes.isEmpty) return;
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

  void _applyBrreg(BrregCompanyDetails d) {
    setState(() {
      _orgLookupCtrl.text = d.orgNumber;
      _nameCtrl.text = d.name;
      _ownerCtrl.text = d.dailyLeaderName ?? _ownerCtrl.text;
      _phoneCtrl.text = d.phone ?? _phoneCtrl.text;
      _emailCtrl.text = d.email ?? _emailCtrl.text;
      _addressCtrl.text = d.street ?? _addressCtrl.text;
      _postalCtrl.text = d.postalCode ?? _postalCtrl.text;
      _cityCtrl.text = d.city ?? _cityCtrl.text;
      _step = 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Hentet ${d.name} fra Brreg')),
    );
  }

  bool _canNext() {
    switch (_step) {
      case 0:
        return true;
      case 1:
        return _nameCtrl.text.trim().isNotEmpty;
      case 2:
        return true;
      default:
        return true;
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
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F1419)
          : const Color(0xFFF3F4F6),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Ny bedrift'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              setState(() => _step--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          PartnerWizardStepper(
            labels: const ['Brreg', 'Bedrift', 'MAVI', 'Lagre'],
            current: _step,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (_step == 0) _stepBrreg(),
                if (_step == 1) _stepCompany(),
                if (_step == 2) _stepVehicles(),
                if (_step == 3) _stepFinish(),
              ],
            ),
          ),
          _navBar(),
        ],
      ),
    );
  }

  Widget _navBar() {
    final isLast = _step == 3;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (_step > 0)
              OutlinedButton(
                onPressed: () => setState(() => _step--),
                child: const Text('Tilbake'),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _saving || !_canNext()
                  ? null
                  : isLast
                      ? _save
                      : () => setState(() => _step++),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
              icon: _saving && isLast
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(isLast ? Icons.check : Icons.arrow_forward),
              label: Text(isLast ? 'Registrer bedrift' : 'Neste'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBrreg() {
    return PartnerBrregLookupPanel(onApply: _applyBrreg);
  }

  Widget _stepCompany() {
    return PartnerSectionCard(
      icon: Icons.storefront_outlined,
      title: 'Bedriftsinformasjon',
      subtitle: _orgLookupCtrl.text.isNotEmpty ? 'Org.nr ${_orgLookupCtrl.text}' : 'Fyll inn manuelt',
      children: [
        PartnerInlineField(label: 'Navn *', controller: _nameCtrl),
        PartnerInlineField(label: 'Eier / kontakt', controller: _ownerCtrl),
        PartnerInlineField(label: 'Telefon', controller: _phoneCtrl, keyboardType: TextInputType.phone),
        PartnerInlineField(label: 'E-post', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
        PartnerInlineField(label: 'Adresse', controller: _addressCtrl),
        Row(
          children: [
            Expanded(child: PartnerInlineField(label: 'Postnr', controller: _postalCtrl)),
            const SizedBox(width: 8),
            Expanded(child: PartnerInlineField(label: 'Sted', controller: _cityCtrl)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: PartnerInlineField(
                label: 'Ant. kjøretøy',
                controller: _vehiclesCtrl,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PartnerInlineField(
                label: 'Nyttelast kg',
                controller: _payloadCtrl,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _euApproved,
          onChanged: (v) => setState(() => _euApproved = v),
          title: const Text('EU-godkjent materiell'),
        ),
        PartnerInlineField(label: 'Notater', controller: _notesCtrl, maxLines: 3),
      ],
    );
  }

  Widget _stepVehicles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartnerSectionCard(
          icon: Icons.directions_car_outlined,
          iconColor: DriftProTheme.accentBlue,
          title: 'Reg.nr (valgfritt)',
          subtitle: 'Kun registreringsnummer, uten MAVI',
          children: [
            ...List.generate(_regOnlyControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _regOnlyControllers[i],
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Reg.nr',
                          border: OutlineInputBorder(),
                          isDense: true,
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
                      icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    ),
                  ],
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: _addRegOnlyRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Reg.nr'),
            ),
          ],
        ),
        PartnerSectionCard(
          icon: Icons.local_shipping_outlined,
          title: 'MAVI & sjåfør',
          subtitle: '${_maviControllers.length} enhet(er) · SMS ved lagring hvis navn+telefon',
          trailing: PartnerStatusBadge(
            label: '${_maviControllers.length}',
            color: DriftProTheme.primaryGreen,
          ),
          children: [
            ...List.generate(_maviControllers.length, (i) {
              final unit = MaviUnitCodes.normalize(_maviControllers[i].text);
              final preview = unit.isEmpty ? '' : PortalCredentials.driverUsername(unit);
              return PartnerMaviRegisterCard(
                index: i,
                maviController: _maviControllers[i],
                driverNameController: _driverNameControllers[i],
                driverPhoneController: _driverPhoneControllers[i],
                usernamePreview: preview,
                onRemove: () {
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
              );
            }),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addMaviRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('MAVI'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _bulkAddMavi,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Lim inn flere'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepFinish() {
    final maviCount = _maviControllers.where((c) => MaviUnitCodes.normalize(c.text).isNotEmpty).length;
    return PartnerSectionCard(
      icon: Icons.fact_check_outlined,
      title: 'Klar til registrering',
      subtitle: 'Sjekk oppsummering før du lagrer',
      children: [
        _summaryRow('Bedrift', _nameCtrl.text.trim().isEmpty ? '—' : _nameCtrl.text.trim()),
        _summaryRow('Org.nr', _orgLookupCtrl.text.isEmpty ? '—' : _orgLookupCtrl.text),
        _summaryRow('Kontakt', _ownerCtrl.text.trim().isEmpty ? '—' : _ownerCtrl.text.trim()),
        _summaryRow('MAVI-enheter', '$maviCount'),
        _summaryRow('Reg.nr', '${_regOnlyControllers.where((c) => c.text.trim().length >= 4).length}'),
        const SizedBox(height: 12),
        PartnerInlineField(
          label: 'Knytt eksisterende bruker (e-post, valgfritt)',
          controller: _inviteEmailCtrl,
          keyboardType: TextInputType.emailAddress,
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: DriftProTheme.labelSm)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
