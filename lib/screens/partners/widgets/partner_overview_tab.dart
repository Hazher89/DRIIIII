import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/vegvesen/vehicle_registry_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';

/// Oversikt: bedriftsinfo, transportløyve, ansatte, kjøretøy med EU per bil.
class PartnerOverviewTab extends StatefulWidget {
  final Partner partner;
  final List<PartnerVehicle> vehicles;
  final Future<void> Function() onSaved;

  const PartnerOverviewTab({
    super.key,
    required this.partner,
    required this.vehicles,
    required this.onSaved,
  });

  @override
  State<PartnerOverviewTab> createState() => _PartnerOverviewTabState();
}

class _VehicleRowState {
  final TextEditingController mavi;
  final TextEditingController reg;
  final TextEditingController payload;
  final TextEditingController year;
  final TextEditingController portalPhone;
  final TextEditingController portalUsername;
  final TextEditingController portalPassword;
  final TextEditingController portalEmail;
  DateTime? euNext;
  DateTime? euLast;
  bool? euApproved;
  List<String> imagePaths;
  Map<String, dynamic>? vegvesenSnapshot;
  String? id;
  bool hasPortalAccount;

  _VehicleRowState({
    required String unitCode,
    required this.reg,
    required this.payload,
    required this.year,
    String? phone,
    String? portalUser,
    String? portalMail,
    this.euNext,
    this.euLast,
    this.euApproved,
    this.imagePaths = const [],
    this.vegvesenSnapshot,
    this.id,
    this.hasPortalAccount = false,
  })  : mavi = TextEditingController(text: unitCode),
        portalPhone = TextEditingController(text: phone ?? ''),
        portalUsername = TextEditingController(text: portalUser ?? ''),
        portalPassword = TextEditingController(),
        portalEmail = TextEditingController(text: portalMail ?? '');
}

class _PartnerOverviewTabState extends State<PartnerOverviewTab> {
  late final TextEditingController _owner;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _postal;
  late final TextEditingController _city;
  late final TextEditingController _veh;
  late final TextEditingController _employees;
  late final TextEditingController _transportCount;
  late final TextEditingController _auditPlate;
  late final TextEditingController _notes;
  bool _hasTransportLicense = false;
  String _auditStatus = 'ukjent';
  final List<_VehicleRowState> _rows = [];
  bool _saving = false;
  bool _portalSaving = false;
  Timer? _vegvesenDebounce;
  Map<String, PartnerPortalAccount> _portalByVehicle = {};

  @override
  void initState() {
    super.initState();
    final p = widget.partner;
    _owner = TextEditingController(text: p.ownerName ?? '');
    _phone = TextEditingController(text: p.phone ?? '');
    _email = TextEditingController(text: p.email ?? '');
    _address = TextEditingController(text: p.address ?? '');
    _postal = TextEditingController(text: p.postalCode ?? '');
    _city = TextEditingController(text: p.city ?? '');
    _veh = TextEditingController(text: '${p.vehicleCountRegistered}');
    _employees = TextEditingController(text: p.employeeCount?.toString() ?? '');
    _transportCount = TextEditingController(text: '${p.transportLicenseCount}');
    _auditPlate = TextEditingController(text: p.auditPlate ?? '');
    _notes = TextEditingController(text: p.notes ?? '');
    _hasTransportLicense = p.hasTransportLicense;
    _auditStatus = p.auditStatus;
    _resetVehicles(widget.vehicles);
    _loadPortals();
  }

  Future<void> _loadPortals() async {
    final accounts = await PartnerService.fetchPortalAccounts(widget.partner.id);
    if (!mounted) return;
    setState(() {
      _portalByVehicle = {
        for (final a in accounts)
          if (a.partnerVehicleId != null) a.partnerVehicleId!: a,
      };
    });
    for (final row in _rows) {
      if (row.id == null) continue;
      final acc = _portalByVehicle[row.id];
      if (acc == null) continue;
      row.portalUsername.text = acc.username;
      row.portalEmail.text = acc.loginEmail;
      row.portalPhone.text = acc.phone ?? row.portalPhone.text;
      row.hasPortalAccount = true;
    }
  }

  @override
  void didUpdateWidget(covariant PartnerOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partner.id != widget.partner.id) return;
    final p = widget.partner;
    _owner.text = p.ownerName ?? '';
    _phone.text = p.phone ?? '';
    _employees.text = p.employeeCount?.toString() ?? '';
    _hasTransportLicense = p.hasTransportLicense;
    _auditStatus = p.auditStatus;
    if (oldWidget.vehicles.length != widget.vehicles.length) {
      _resetVehicles(widget.vehicles);
      _loadPortals();
    }
  }

  void _resetVehicles(List<PartnerVehicle> vehicles) {
    for (final r in _rows) {
      r.mavi.dispose();
      r.reg.dispose();
      r.payload.dispose();
      r.year.dispose();
      r.portalPhone.dispose();
      r.portalUsername.dispose();
      r.portalPassword.dispose();
      r.portalEmail.dispose();
    }
    _rows.clear();
    if (vehicles.isEmpty) return;
    for (final v in vehicles) {
      final acc = _portalByVehicle[v.id];
      final regDisplay = v.registrationNumber == MaviUnitCodes.regNrPlaceholder
          ? ''
          : v.registrationNumber;
      _rows.add(_VehicleRowState(
        id: v.id,
        unitCode: MaviUnitCodes.normalize(v.unitCode),
        phone: v.phone ?? acc?.phone,
        portalUser: acc?.username,
        portalMail: acc?.loginEmail,
        hasPortalAccount: acc != null,
        reg: TextEditingController(text: regDisplay),
        payload: TextEditingController(text: v.payloadKg?.toString() ?? ''),
        year: TextEditingController(text: v.modelYear?.toString() ?? ''),
        euNext: v.euNextAt,
        euLast: v.euLastAt,
        euApproved: v.euApproved,
        imagePaths: List.from(v.imageUrls),
        vegvesenSnapshot: v.vegvesenSnapshot,
      ));
    }
  }

  Future<void> _saveVehiclePortal(_VehicleRowState row) async {
    if (row.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lagre MAVI først, deretter portal-konto.')),
      );
      return;
    }
    final user = row.portalUsername.text.trim();
    final phone = row.portalPhone.text.trim();
    if (user.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brukernavn og telefon (SMS) er påkrevd.')),
      );
      return;
    }
    var email = row.portalEmail.text.trim();
    if (!email.contains('@')) {
      email = PartnerService.suggestedPortalLoginEmail(
        username: user,
        companyId: widget.partner.companyId,
      );
      row.portalEmail.text = email;
    }
    setState(() => _portalSaving = true);
    try {
      await PartnerService.provisionVehiclePortal(
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        partnerVehicleId: row.id!,
        username: user,
        loginEmail: email,
        phone: phone,
        password: row.portalPassword.text.trim().isEmpty ? null : row.portalPassword.text,
      );
      row.hasPortalAccount = true;
      row.portalPassword.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portal lagret for $user · SMS til $phone')),
        );
      }
      await _loadPortals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre portal: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _portalSaving = false);
    }
  }

  Future<void> _deleteVehiclePortal(_VehicleRowState row) async {
    if (row.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett portal-konto?'),
        content: const Text('Brukeren kan ikke lenger logge inn. Dette deaktiveres i Supabase.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PartnerService.deleteVehiclePortal(
      partnerVehicleId: row.id!,
      partnerId: widget.partner.id,
      companyId: widget.partner.companyId,
    );
    row.portalUsername.clear();
    row.portalPassword.clear();
    row.portalEmail.clear();
    row.hasPortalAccount = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Portal-konto deaktivert')));
    }
    await _loadPortals();
  }

  List<String> get _existingMaviCodes => _rows
      .map((r) => MaviUnitCodes.normalize(r.mavi.text))
      .where((s) => s.isNotEmpty)
      .toList();

  void _addMaviRow({String? unitCode}) {
    setState(() {
      _rows.add(_VehicleRowState(
        unitCode: unitCode ?? MaviUnitCodes.suggestNext(_existingMaviCodes),
        reg: TextEditingController(),
        payload: TextEditingController(),
        year: TextEditingController(),
      ));
    });
  }

  Future<void> _bulkAddMavi() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legg til flere MAVI-nummer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Én per linje (eller kommaseparert). Eksempel:\n'
                'M0001\nM0002\nNO_O_M0044',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'M0001\nM0002\nM0003',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty),
            child: const Text('Legg til'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final codes = MaviUnitCodes.parseBulk(ctrl.text);
    if (codes.isEmpty) return;
    setState(() {
      final existing = _existingMaviCodes.toSet();
      for (final code in codes) {
        if (existing.contains(code)) continue;
        existing.add(code);
        _rows.add(_VehicleRowState(
          unitCode: code,
          reg: TextEditingController(),
          payload: TextEditingController(),
          year: TextEditingController(),
        ));
      }
    });
  }

  void _scheduleVegvesenLookup(_VehicleRowState row) {
    final plate = row.reg.text.trim().replaceAll(RegExp(r'\s'), '');
    if (plate.length < 4) return;
    _vegvesenDebounce?.cancel();
    _vegvesenDebounce = Timer(const Duration(milliseconds: 900), () {
      if (mounted) _lookupVegvesen(row, silent: true);
    });
  }

  @override
  void dispose() {
    _vegvesenDebounce?.cancel();
    _owner.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _postal.dispose();
    _city.dispose();
    _veh.dispose();
    _employees.dispose();
    _transportCount.dispose();
    _auditPlate.dispose();
    _notes.dispose();
    for (final r in _rows) {
      r.mavi.dispose();
      r.reg.dispose();
      r.payload.dispose();
      r.year.dispose();
    }
    super.dispose();
  }

  Future<void> _lookupVegvesen(_VehicleRowState row, {bool silent = false}) async {
    final plate = row.reg.text.trim().replaceAll(RegExp(r'\s'), '');
    if (plate.length < 4) return;
    if (!silent) setState(() => _saving = true);
    try {
      final data = await VehicleRegistryService.lookup(plate);
      if (data == null) {
        if (mounted && !silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Vegvesen-API ikke konfigurert. Sett VEGVESEN_API_KEY og deploy vehicle-lookup.',
              ),
            ),
          );
        }
        return;
      }
      setState(() {
        if (data.modelYear != null) row.year.text = '${data.modelYear}';
        if (data.payloadKg != null) row.payload.text = '${data.payloadKg}';
        row.euNext = data.euNextAt;
        row.euLast = data.euLastAt;
        row.euApproved = data.euNextAt != null &&
            !data.euNextAt!.isBefore(DateTime.now());
        row.vegvesenSnapshot = data.raw;
      });
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data.euNextAt != null
                  ? 'Hentet fra Vegvesen — neste EU ${data.euNextAt!.day}.${data.euNextAt!.month}.${data.euNextAt!.year}'
                  : 'Hentet data for $plate fra Vegvesen',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vegvesen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted && !silent) setState(() => _saving = false);
    }
  }

  Future<void> _addVehicleImage(_VehicleRowState row) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      for (final f in picked.files) {
        if (f.bytes == null) continue;
        final path = await PartnerService.uploadVehicleImage(
          companyId: widget.partner.companyId,
          partnerId: widget.partner.id,
          unitCode: MaviUnitCodes.normalize(row.mavi.text),
          fileName: f.name,
          bytes: f.bytes!,
        );
        row.imagePaths.add(path);
      }
      setState(() {});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final p = widget.partner;
      final updated = Partner(
        id: p.id,
        companyId: p.companyId,
        orgNumber: p.orgNumber,
        name: p.name,
        tradeName: p.tradeName,
        ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        postalCode: _postal.text.trim().isEmpty ? null : _postal.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        country: p.country,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        vehicleCountRegistered: int.tryParse(_veh.text) ?? _rows.length,
        vehicleMaxPayloadKg: null,
        euApproved: null,
        hasTransportLicense: _hasTransportLicense,
        transportLicenseCount:
            int.tryParse(_transportCount.text) ?? 0,
        employeeCount: int.tryParse(_employees.text),
        auditStatus: _auditStatus,
        auditPlate:
            _auditPlate.text.trim().isEmpty ? null : _auditPlate.text.trim(),
        brregSnapshot: p.brregSnapshot,
        lastMeetingAt: p.lastMeetingAt,
        nextMeetingAt: p.nextMeetingAt,
        lastAuditAt: p.lastAuditAt,
        nextAuditAt: p.nextAuditAt,
        createdAt: p.createdAt,
      );
      await PartnerService.updatePartner(p.id, updated);

      final vehicles = <PartnerVehicle>[];
      final seenUnits = <String>{};
      for (final row in _rows) {
        final unit = MaviUnitCodes.normalize(row.mavi.text);
        if (unit.isEmpty || seenUnits.contains(unit)) continue;
        seenUnits.add(unit);
        final regRaw = row.reg.text.trim().toUpperCase();
        final reg = regRaw.isEmpty ? MaviUnitCodes.regNrPlaceholder : regRaw;
        vehicles.add(
          PartnerVehicle(
            id: row.id ?? '',
            partnerId: p.id,
            companyId: p.companyId,
            unitCode: unit,
            registrationNumber: reg,
            phone: row.portalPhone.text.trim().isEmpty ? null : row.portalPhone.text.trim(),
            modelYear: int.tryParse(row.year.text),
            payloadKg: int.tryParse(row.payload.text),
            euLastAt: row.euLast,
            euNextAt: row.euNext,
            euApproved: row.euApproved,
            imageUrls: row.imagePaths,
            vegvesenSnapshot: row.vegvesenSnapshot,
            createdAt: DateTime.now(),
          ),
        );
      }
      await PartnerService.replaceVehicles(
        partnerId: p.id,
        companyId: p.companyId,
        vehicles: vehicles,
      );
      await _loadPortals();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret')),
        );
        await widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.partner;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Org.nr ${p.orgNumber ?? "—"}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            _field('Eier / kontakt', _owner),
            _field('Telefon (SMS-varsler)', _phone),
            _field('E-post', _email),
            _field('Adresse', _address),
            Row(
              children: [
                Expanded(child: _field('Postnr', _postal)),
                const SizedBox(width: 8),
                Expanded(child: _field('Sted', _city)),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field('Ant. kjøretøy (bedrift)', _veh)),
                const SizedBox(width: 8),
                Expanded(child: _field('Ant. ansatte', _employees)),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Har transportløyve'),
              value: _hasTransportLicense,
              onChanged: (v) => setState(() => _hasTransportLicense = v),
            ),
            if (_hasTransportLicense)
              _field('Antall transportløyver', _transportCount),
            const Divider(height: 32),
            Text('Revisjon / audit', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _auditStatus,
              decoration: const InputDecoration(
                labelText: 'Audit-status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'ukjent', child: Text('Ukjent')),
                DropdownMenuItem(value: 'planlagt', child: Text('Planlagt')),
                DropdownMenuItem(value: 'ok', child: Text('OK')),
                DropdownMenuItem(value: 'avvik', child: Text('Avvik')),
                DropdownMenuItem(value: 'utlopt', child: Text('Utløpt')),
              ],
              onChanged: (v) => setState(() => _auditStatus = v ?? 'ukjent'),
            ),
            const SizedBox(height: 8),
            _field('Audit — reg.nr / skilt', _auditPlate),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAVI-nummer', style: DriftProTheme.headingSm),
                      Text(
                        '${_rows.length} registrert på denne bedriften — du kan legge til så mange du vil.',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                Text('${_rows.length}', style: DriftProTheme.headingMd),
              ],
            ),
            const SizedBox(height: 8),
            if (_rows.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Ingen MAVI-nummer ennå. Legg til ett eller flere under.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._rows.asMap().entries.map((e) => _vehicleCard(e.key, e.value)),
            const SizedBox(height: 8),
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
            _field('Notater', _notes, maxLines: 3),
            const SizedBox(height: 80),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Lagre endringer'),
            ),
          ],
        ),
        if (_saving)
          const ModalBarrier(dismissible: false),
        if (_saving)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _vehicleCard(int index, _VehicleRowState row) {
    Color? border;
    if (row.euNext != null && row.euNext!.isBefore(DateTime.now())) {
      border = DriftProTheme.error;
    } else if (row.euNext != null &&
        row.euNext!.isBefore(DateTime.now().add(const Duration(days: 60)))) {
      border = DriftProTheme.warning;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border ?? Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.mavi,
                    decoration: const InputDecoration(
                      labelText: 'MAVI-nummer *',
                      hintText: 'NO_O_M0001 eller M1',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fjern MAVI',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      row.mavi.dispose();
                      row.reg.dispose();
                      row.payload.dispose();
                      row.year.dispose();
                      row.portalPhone.dispose();
                      row.portalUsername.dispose();
                      row.portalPassword.dispose();
                      row.portalEmail.dispose();
                      _rows.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.reg,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Reg.nr (valgfritt)',
                      hintText: 'EU hentes automatisk',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _scheduleVegvesenLookup(row),
                  ),
                ),
                IconButton(
                  tooltip: 'Hent fra Vegvesen nå',
                  onPressed: () => _lookupVegvesen(row),
                  icon: const Icon(Icons.cloud_download_outlined),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Årsmodell',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: row.payload,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nyttelast kg',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Neste EU-kontroll'),
              subtitle: Text(
                row.euNext != null
                    ? '${row.euNext!.day}.${row.euNext!.month}.${row.euNext!.year}'
                    : 'Ikke satt — bruk Vegvesen-knapp',
              ),
              trailing: const Icon(Icons.calendar_today, size: 20),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: row.euNext ?? DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime(2010),
                  lastDate: DateTime(2040),
                );
                if (d != null) setState(() => row.euNext = d);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('EU-godkjent'),
              value: row.euApproved ?? false,
              onChanged: (v) => setState(() => row.euApproved = v),
            ),
            const Divider(height: 24),
            Text('Sjåførportal (per MAVI)', style: DriftProTheme.headingSm.copyWith(fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Telefon brukes til SMS når rute sendes. Brukernavn/passord gir innlogging på samarbeidspartner-siden.',
              style: TextStyle(fontSize: 11, height: 1.3, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.portalPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefon (SMS-varsler) *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.portalUsername,
              decoration: const InputDecoration(
                labelText: 'Brukernavn *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.portalPassword,
              obscureText: true,
              decoration: InputDecoration(
                labelText: row.hasPortalAccount ? 'Nytt passord (tom = behold)' : 'Passord *',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.portalEmail,
              decoration: const InputDecoration(
                labelText: 'Innloggings-e-post',
                hintText: 'Genereres automatisk om tom',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _portalSaving ? null : () => _saveVehiclePortal(row),
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                    ),
                    child: Text(row.hasPortalAccount ? 'Oppdater portal' : 'Opprett portal'),
                  ),
                ),
                if (row.hasPortalAccount) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Slett portal',
                    onPressed: _portalSaving ? null : () => _deleteVehiclePortal(row),
                    icon: const Icon(Icons.link_off, color: Colors.red),
                  ),
                ],
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _addVehicleImage(row),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text('Bilder (${row.imagePaths.length})'),
                ),
              ],
            ),
            if (row.imagePaths.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: row.imagePaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => Chip(
                    label: Text('Bilde ${i + 1}', style: const TextStyle(fontSize: 10)),
                    onDeleted: () => setState(() => row.imagePaths.removeAt(i)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
