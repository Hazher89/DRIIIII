import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/sms/sms_phone_utils.dart';
import '../../../core/utils/portal_credentials.dart';
import '../../../core/constants/mavi_fleet_roles.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/services/vegvesen/vehicle_registry_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'partner_companies_ui.dart';
import 'eco_driving_badge.dart';
import 'partner_modern_ui.dart';
import 'partner_ui.dart';

String _friendlyPartnerSaveError(Object error) {
  final msg = error.toString();
  if (msg.contains('uq_partner_portal_email') ||
      (msg.contains('23505') && msg.contains('login_email'))) {
    return 'E-postadressen er allerede knyttet til en annen portal-bruker. '
        'Hver bil-eier får eget brukernavn — kontakt-e-post under «Kontakt & bedrift» '
        'brukes kun til varsler og skal ikke overskrive innlogging.';
  }
  if (msg.contains('23505')) {
    return 'Verdien finnes allerede i systemet (duplikat).';
  }
  return msg.length > 200 ? '${msg.substring(0, 197)}…' : msg;
}

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
  final bool isRegOnly;
  final TextEditingController mavi;
  final TextEditingController reg;
  final TextEditingController driverName;
  final TextEditingController payload;
  final TextEditingController year;
  final TextEditingController portalPhone;
  String? portalUsername;
  String? generatedPasswordPreview;
  DateTime? euNext;
  DateTime? euLast;
  bool? euApproved;
  List<String> imagePaths;
  Map<String, dynamic>? vegvesenSnapshot;
  String? id;
  bool hasPortalAccount;
  Set<String> fleetRoles;
  bool isActive;

  _VehicleRowState({
    this.isRegOnly = false,
    required String unitCode,
    required this.reg,
    String? driverNameText,
    required this.payload,
    required this.year,
    String? phone,
    this.portalUsername,
    this.generatedPasswordPreview,
    this.euNext,
    this.euLast,
    this.euApproved,
    this.imagePaths = const [],
    this.vegvesenSnapshot,
    this.id,
    this.hasPortalAccount = false,
    Set<String>? fleetRoles,
    this.isActive = true,
  })  : fleetRoles = fleetRoles ?? {},
        mavi = TextEditingController(text: isRegOnly ? '' : unitCode),
        driverName = TextEditingController(text: driverNameText ?? ''),
        portalPhone = TextEditingController(text: phone ?? '');

  String get previewUsername {
    if (isRegOnly) return '';
    final unit = MaviUnitCodes.normalize(mavi.text);
    if (unit.isEmpty) return '';
    return PortalCredentials.driverUsername(unit);
  }
}

class _OwnerPortalRowState {
  final TextEditingController phone;
  final TextEditingController displayName;
  String? accountId;
  String? username;
  String? savedNormalizedPhone;
  bool hasPortalAccount;
  bool pendingPhoneReplace;
  Timer? phoneDebounce;

  _OwnerPortalRowState({
    String? phone,
    String? name,
    this.accountId,
    this.username,
    this.savedNormalizedPhone,
    this.hasPortalAccount = false,
  })  : phone = TextEditingController(text: phone ?? ''),
        displayName = TextEditingController(text: name ?? ''),
        pendingPhoneReplace = false;

  factory _OwnerPortalRowState.fromAccount(PartnerPortalAccount account) {
    return _OwnerPortalRowState(
      phone: account.phone,
      accountId: account.id,
      username: account.username,
      savedNormalizedPhone: account.phone != null ? normalizePhoneNo(account.phone!) : null,
      hasPortalAccount: true,
    );
  }

  void dispose() {
    phoneDebounce?.cancel();
    phone.dispose();
    displayName.dispose();
  }

  String previewUsername({
    required String partnerName,
    String? orgNumber,
    String? partnerId,
  }) {
    final normalized = normalizePhoneNo(phone.text.trim()) ?? phone.text.trim();
    return PortalCredentials.ownerUsername(
      partnerName: partnerName,
      orgNumber: orgNumber,
      partnerId: partnerId,
      phone: normalized.isEmpty ? null : normalized,
    );
  }

  bool phoneChangedFromSaved() {
    if (!hasPortalAccount || savedNormalizedPhone == null) return false;
    final current = normalizePhoneNo(phone.text.trim());
    return current != null && current != savedNormalizedPhone;
  }
}

enum _OverviewSection {
  profile('Bedrift'),
  routing('Ruter'),
  ownerPortal('Bedriftsansvarlig'),
  registrations('Skiltnummer'),
  maviDrivers('MAVI Nummer');

  const _OverviewSection(this.label);
  final String label;
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
  final List<_VehicleRowState> _rows = [];
  bool _saving = false;
  bool _portalSaving = false;
  bool _routesOwnerOnly = false;
  bool _routesOwnerOnlySaving = false;
  bool _ecoDrivingCompleted = false;
  DateTime? _ecoDrivingDeadline;
  DateTime? _ecoDrivingCompletedAt;
  bool _isSuperAdmin = false;
  Timer? _vegvesenDebounce;
  final Set<_VehicleRowState> _vegvesenLoading = {};
  Map<String, PartnerPortalAccount> _portalByVehicle = {};
  final List<_OwnerPortalRowState> _ownerRows = [];
  _OverviewSection _activeSection = _OverviewSection.profile;
  List<PartnerVehicleInspection> _inspections = [];

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
    _routesOwnerOnly = p.routesOwnerOnly;
    _ecoDrivingCompleted = p.ecoDrivingCompleted;
    _ecoDrivingDeadline = p.ecoDrivingDeadline;
    _ecoDrivingCompletedAt = p.ecoDrivingCompletedAt;
    _ownerRows.add(_OwnerPortalRowState(phone: widget.partner.phone));
    _resetVehicles(widget.vehicles);
    _loadPortals();
    _loadInspections();
    _loadCurrentUser();
  }

  Future<void> _loadInspections() async {
    final list = await PartnerService.fetchVehicleInspections(widget.partner.id);
    if (!mounted) return;
    setState(() => _inspections = list);
  }

  Map<String, PartnerVehicleInspection> get _inspectionByVehicleId =>
      PartnerVehicleInspection.latestByVehicleId(widget.vehicles, _inspections);

  Future<void> _loadCurrentUser() async {
    final profile = await SupabaseService.fetchEffectiveUserProfile();
    if (!mounted) return;
    setState(() => _isSuperAdmin = profile?.isSuperAdmin == true);
  }

  Future<bool> _confirmSendNewPassword({required String who, required String phone}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send nytt passord?'),
        content: Text(
          'Generer nytt passord og send på SMS til $who ($phone)?\n\n'
          'Gammelt passord slutter å virke umiddelbart.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send SMS')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _loadPortals() async {
    final accounts = await PartnerService.fetchPortalAccounts(widget.partner.id);
    if (!mounted) return;
    final owners = accounts.where((a) => a.isOwner).toList();
    final byVehicle = <String, PartnerPortalAccount>{};
    for (final a in accounts) {
      if (!a.isOwner && a.partnerVehicleId != null) {
        byVehicle[a.partnerVehicleId!] = a;
      }
    }
    setState(() {
      _portalByVehicle = byVehicle;
      for (final row in _ownerRows) {
        row.dispose();
      }
      _ownerRows
        ..clear()
        ..addAll(
          owners.isEmpty
              ? [_OwnerPortalRowState(phone: widget.partner.phone)]
              : owners.map(_OwnerPortalRowState.fromAccount),
        );
    });
    for (final row in _rows) {
      if (row.id == null) continue;
      final acc = _portalByVehicle[row.id];
      if (acc == null) continue;
      row.portalUsername = acc.username;
      row.portalPhone.text = acc.phone ?? row.portalPhone.text;
      row.hasPortalAccount = true;
    }
  }

  String _portalSmsStatusLine(PortalProvisionResult res) {
    if (res.smsSent) {
      final dest = res.phone != null ? ' (${displayPhoneNo(res.phone!)})' : '';
      return 'Sendt på SMS til telefonnummeret$dest.';
    }
    if (res.smsQueued) {
      return 'SMS ligger i sendekø — ikke bekreftet levert. Del opplysningene manuelt hvis den ikke kommer.';
    }
    final err = res.smsError?.trim();
    if (err != null && err.isNotEmpty) {
      return 'SMS kunne ikke sendes: $err\nDel opplysningene manuelt.';
    }
    return 'SMS kunne ikke sendes — del opplysningene manuelt.';
  }

  Future<void> _showCredentialsDialog(PortalProvisionResult res, {required String title}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(
          'Brukernavn: ${res.username}\n'
          'Passord: ${res.password}\n\n'
          'Logg inn på driftpro.no med brukernavn og passord.\n\n'
          '${_portalSmsStatusLine(res)}',
        ),
        actions: [
          if (!res.smsSent)
            TextButton(
              onPressed: () async {
                final flush = await PartnerService.flushSmsOutbox();
                if (!ctx.mounted) return;
                final sent = (flush?['sent'] as num?)?.toInt() ?? 0;
                if (sent > 0) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SMS sendt via Sveve')),
                  );
                } else {
                  final err = flush?['error'] as String? ??
                      (flush?['details'] is List && (flush!['details'] as List).isNotEmpty
                          ? ((flush['details'] as List).first as Map)['error']?.toString()
                          : null);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err ?? 'Kunne ikke sende SMS — sjekk telefonnummer og Sveve'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Prøv SMS igjen'),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _setRoutesOwnerOnly(bool value) async {
    setState(() {
      _routesOwnerOnly = value;
      _routesOwnerOnlySaving = true;
    });
    try {
      await PartnerService.updatePartnerFields(widget.partner.id, {
        'routes_owner_only': value,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Kun bedriftsansvarlig får SMS-varsel. Sjåfør ser fortsatt ruter på egen bil i portal.'
                  : 'Bedriftsansvarlig og sjåfør får SMS-varsel. Sjåfør ser fortsatt kun ruter på egen bil.',
            ),
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _routesOwnerOnly = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: ${_friendlyPartnerSaveError(e)}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _routesOwnerOnlySaving = false);
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
    _routesOwnerOnly = p.routesOwnerOnly;
    _ecoDrivingCompleted = p.ecoDrivingCompleted;
    _ecoDrivingDeadline = p.ecoDrivingDeadline;
    _ecoDrivingCompletedAt = p.ecoDrivingCompletedAt;
    if (_vehiclesDiffer(oldWidget.vehicles, widget.vehicles)) {
      _resetVehicles(widget.vehicles);
      _loadPortals();
    }
  }

  bool _vehiclesDiffer(List<PartnerVehicle> a, List<PartnerVehicle> b) {
    if (a.length != b.length) return true;
    final aKeys = a.map((v) => '${v.id}|${v.unitCode}').toSet();
    final bKeys = b.map((v) => '${v.id}|${v.unitCode}').toSet();
    return aKeys.length != bKeys.length || !aKeys.containsAll(bKeys);
  }

  void _resetVehicles(List<PartnerVehicle> vehicles) {
    for (final r in _rows) {
      r.mavi.dispose();
      r.reg.dispose();
      r.driverName.dispose();
      r.payload.dispose();
      r.year.dispose();
      r.portalPhone.dispose();
    }
    _rows.clear();
    if (vehicles.isEmpty) return;

    final regPlatesAdded = <String>{};

    void addRegRow(PartnerVehicle v, {required String regDisplay}) {
      final plate = regDisplay.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
      if (plate.length < 4 || regPlatesAdded.contains(plate)) return;
      regPlatesAdded.add(plate);
      _rows.add(_VehicleRowState(
        isRegOnly: true,
        id: v.vehicleKind == 'registration' ||
                MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode)
            ? v.id
            : null,
        unitCode: '',
        reg: TextEditingController(text: plate),
        payload: TextEditingController(text: v.payloadKg?.toString() ?? ''),
        year: TextEditingController(text: v.modelYear?.toString() ?? ''),
        euNext: v.euNextAt,
        euLast: v.euLastAt,
        euApproved: v.euApproved,
        imagePaths: List.from(v.imageUrls),
        vegvesenSnapshot: v.vegvesenSnapshot,
      ));
    }

    for (final v in vehicles) {
      if (v.vehicleKind != 'registration' &&
          !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode)) {
        continue;
      }
      final regDisplay = MaviUnitCodes.plateFromRegistrationUnit(v.unitCode).isNotEmpty
          ? MaviUnitCodes.plateFromRegistrationUnit(v.unitCode)
          : (v.registrationNumber == MaviUnitCodes.regNrPlaceholder
              ? ''
              : v.registrationNumber);
      addRegRow(v, regDisplay: regDisplay);
    }

    for (final v in vehicles) {
      if (v.vehicleKind == 'registration' ||
          MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode)) {
        continue;
      }
      final acc = _portalByVehicle[v.id];
      final regLink = v.registrationNumber == MaviUnitCodes.regNrPlaceholder
          ? ''
          : v.registrationNumber.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
      final hasVehicleMeta = v.modelYear != null ||
          v.payloadKg != null ||
          v.euNextAt != null ||
          v.euLastAt != null ||
          v.euApproved != null ||
          v.vegvesenSnapshot != null;
      if (regLink.length >= 4 && hasVehicleMeta) {
        addRegRow(v, regDisplay: regLink);
      }
      _rows.add(_VehicleRowState(
        isRegOnly: false,
        id: v.id,
        unitCode: MaviUnitCodes.normalize(v.unitCode),
        driverNameText: v.driverName,
        phone: v.phone ?? acc?.phone,
        portalUsername: acc?.username,
        hasPortalAccount: acc != null,
        fleetRoles: MaviFleetRoles.normalize(v.fleetRoles).toSet(),
        isActive: v.isActive,
        reg: TextEditingController(text: regLink),
        payload: TextEditingController(),
        year: TextEditingController(),
        imagePaths: List.from(v.imageUrls),
      ));
    }

    _scheduleInitialVegvesenLookups();
  }

  void _scheduleInitialVegvesenLookups() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final row in _rows.where((r) => r.isRegOnly)) {
        final plate = row.reg.text.trim().replaceAll(RegExp(r'\s'), '');
        if (plate.length < 4) continue;
        if (row.euNext == null ||
            row.year.text.trim().isEmpty ||
            row.payload.text.trim().isEmpty) {
          _scheduleVegvesenLookup(row);
        }
      }
    });
  }

  void _scheduleOwnerPhoneReplaceCheck(_OwnerPortalRowState row) {
    row.phoneDebounce?.cancel();
    if (!row.hasPortalAccount || !row.phoneChangedFromSaved()) {
      if (mounted && row.pendingPhoneReplace) {
        setState(() => row.pendingPhoneReplace = false);
      }
      return;
    }
    row.phoneDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted || !row.phoneChangedFromSaved()) return;
      await _deleteOwnerPortalAccount(row, silent: true);
      if (mounted) {
        setState(() => row.pendingPhoneReplace = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gammel bil-eier-konto er slettet. Send innlogging til det nye nummeret.'),
          ),
        );
      }
    });
  }

  Future<void> _deleteOwnerPortalAccount(_OwnerPortalRowState row, {bool silent = false}) async {
    if (row.accountId == null) {
      row.hasPortalAccount = false;
      row.username = null;
      row.savedNormalizedPhone = null;
      row.pendingPhoneReplace = false;
      return;
    }
    await PartnerService.deleteOwnerPortal(
      partnerId: widget.partner.id,
      companyId: widget.partner.companyId,
      portalAccountId: row.accountId,
    );
    row.accountId = null;
    row.username = null;
    row.savedNormalizedPhone = null;
    row.hasPortalAccount = false;
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bil-eier-portal deaktivert')),
      );
    }
  }

  Future<void> _removeOwnerPortalRow(_OwnerPortalRowState row) async {
    if (row.hasPortalAccount) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Slett bil-eier-portal?'),
          content: const Text('Bil-eieren kan ikke lenger logge inn på DriftPro.'),
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
      await _deleteOwnerPortalAccount(row);
    }
    if (!mounted) return;
    setState(() {
      row.dispose();
      _ownerRows.remove(row);
      if (_ownerRows.isEmpty) {
        _ownerRows.add(_OwnerPortalRowState(phone: widget.partner.phone));
      }
    });
  }

  void _addOwnerPortalRow() {
    setState(() => _ownerRows.add(_OwnerPortalRowState()));
  }

  Future<void> _saveOwnerPortal(_OwnerPortalRowState row) async {
    if (row.hasPortalAccount) return;
    final phone = row.phone.text.trim();
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon til bedriftsansvarlig er påkrevd (SMS med innlogging).')),
      );
      return;
    }
    setState(() => _portalSaving = true);
    try {
      final res = await PartnerService.provisionOwnerPortal(
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        phone: phone,
        partnerName: widget.partner.name,
        orgNumber: widget.partner.orgNumber,
        ownerDisplayName: row.displayName.text.trim().isEmpty ? null : row.displayName.text.trim(),
      );
      row.pendingPhoneReplace = false;
      await _showCredentialsDialog(res, title: 'Portal for bedriftsansvarlig opprettet');
      await _loadPortals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette bedriftsansvarlig: ${_friendlyPartnerSaveError(e)}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _portalSaving = false);
    }
  }

  Future<void> _resendOwnerPortalPassword(_OwnerPortalRowState row) async {
    if (!row.hasPortalAccount) return;
    final phone = row.phone.text.trim();
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon til bedriftsansvarlig er påkrevd (SMS med innlogging).')),
      );
      return;
    }
    final who = row.displayName.text.trim().isEmpty ? 'bedriftsansvarlig' : row.displayName.text.trim();
    if (!await _confirmSendNewPassword(who: who, phone: phone)) return;
    setState(() => _portalSaving = true);
    try {
      final res = await PartnerService.resendOwnerPortalPassword(
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        phone: phone,
        partnerName: widget.partner.name,
        orgNumber: widget.partner.orgNumber,
        portalAccountId: row.accountId,
        ownerDisplayName: row.displayName.text.trim().isEmpty ? null : row.displayName.text.trim(),
      );
      await _showCredentialsDialog(res, title: 'Nytt passord sendt til bedriftsansvarlig');
      await _loadPortals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende nytt passord: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _portalSaving = false);
    }
  }

  Future<void> _saveVehiclePortal(_VehicleRowState row) async {
    if (row.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lagre bedriften først (MAVI), deretter sjåfør-portal.')),
      );
      return;
    }
    final phone = row.portalPhone.text.trim();
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon (SMS) er påkrevd for sjåfør.')),
      );
      return;
    }
    final driverName = row.driverName.text.trim();
    if (driverName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv inn sjåførens navn.')),
      );
      return;
    }
    final unit = MaviUnitCodes.normalize(row.mavi.text);
    if (unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn MAVI-nummer først.')),
      );
      return;
    }
    if (row.hasPortalAccount) return;
    setState(() => _portalSaving = true);
    try {
      final res = await PartnerService.provisionDriverPortal(
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        partnerVehicleId: row.id!,
        unitCode: unit,
        phone: phone,
        driverName: driverName,
      );
      row.hasPortalAccount = true;
      row.portalUsername = res.username;
      row.generatedPasswordPreview = res.password;
      await _showCredentialsDialog(res, title: 'Sjåfør opprettet');
      await _loadPortals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sjåfør-portal feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _portalSaving = false);
    }
  }

  Future<void> _resendDriverPortalPassword(_VehicleRowState row) async {
    if (row.id == null || !row.hasPortalAccount) return;
    final phone = row.portalPhone.text.trim();
    if (phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon (SMS) er påkrevd for sjåfør.')),
      );
      return;
    }
    final driverName = row.driverName.text.trim();
    if (driverName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv inn sjåførens navn.')),
      );
      return;
    }
    final unit = MaviUnitCodes.normalize(row.mavi.text);
    if (unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn MAVI-nummer først.')),
      );
      return;
    }
    if (!await _confirmSendNewPassword(who: driverName, phone: phone)) return;
    setState(() => _portalSaving = true);
    try {
      final res = await PartnerService.resendDriverPortalPassword(
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        partnerVehicleId: row.id!,
        unitCode: unit,
        phone: phone,
        driverName: driverName,
      );
      row.portalUsername = res.username;
      row.generatedPasswordPreview = res.password;
      await _showCredentialsDialog(res, title: 'Nytt passord sendt til sjåfør');
      await _loadPortals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende nytt passord: $e'), backgroundColor: Colors.red),
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
        title: const Text('Slett sjåfør-portal?'),
        content: const Text('Sjåføren kan ikke lenger logge inn på DriftPro.'),
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
    await PartnerService.deleteDriverPortal(
      partnerVehicleId: row.id!,
      partnerId: widget.partner.id,
      companyId: widget.partner.companyId,
    );
    row.portalUsername = null;
    row.hasPortalAccount = false;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sjåfør-portal deaktivert')));
    }
    await _loadPortals();
  }

  List<String> get _existingMaviCodes => _rows
      .where((r) => !r.isRegOnly)
      .map((r) => MaviUnitCodes.normalize(r.mavi.text))
      .where((s) => s.isNotEmpty)
      .toList();

  List<String> get _registeredPlates => _rows
      .where((r) => r.isRegOnly)
      .map((r) => r.reg.text.trim().toUpperCase().replaceAll(RegExp(r'\s'), ''))
      .where((s) => s.length >= 4)
      .toList();

  void _addRegRow() {
    setState(() {
      _rows.add(_VehicleRowState(
        isRegOnly: true,
        unitCode: '',
        reg: TextEditingController(),
        payload: TextEditingController(),
        year: TextEditingController(),
      ));
    });
  }

  void _addMaviRow({String? unitCode}) {
    setState(() {
      final row = _VehicleRowState(
        isRegOnly: false,
        unitCode: unitCode ?? MaviUnitCodes.suggestNext(_existingMaviCodes),
        reg: TextEditingController(),
        payload: TextEditingController(),
        year: TextEditingController(),
      );
      row.generatedPasswordPreview = PortalCredentials.generatePassword();
      _rows.add(row);
    });
  }

  Future<void> _bulkAddMavi() async {
    final codes = await PartnerCompaniesUi.showMaviBulkPasteDialog(context);
    if (codes.isEmpty) return;
    setState(() {
      final existing = _existingMaviCodes.toSet();
      for (final code in codes) {
        if (existing.contains(code)) continue;
        existing.add(code);
        _rows.add(_VehicleRowState(
          isRegOnly: false,
          unitCode: code,
          reg: TextEditingController(),
          payload: TextEditingController(),
          year: TextEditingController(),
          generatedPasswordPreview: PortalCredentials.generatePassword(),
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
    for (final r in _ownerRows) {
      r.dispose();
    }
    for (final r in _rows) {
      r.mavi.dispose();
      r.reg.dispose();
      r.driverName.dispose();
      r.payload.dispose();
      r.year.dispose();
      r.portalPhone.dispose();
    }
    super.dispose();
  }

  Future<void> _lookupVegvesen(_VehicleRowState row, {bool silent = false}) async {
    final plate = row.reg.text.trim().replaceAll(RegExp(r'\s'), '');
    if (plate.length < 4) return;
    if (!silent) setState(() => _saving = true);
    if (mounted) setState(() => _vegvesenLoading.add(row));
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
      final gotFields = data.modelYear != null ||
          data.payloadKg != null ||
          data.euNextAt != null ||
          (data.make?.isNotEmpty ?? false);
      if (mounted && !silent) {
        if (!gotFields) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Vegvesen fant ikke tekniske data for $plate. '
                'Sjekk at reg.nr er riktig og registrert i Norge.',
              ),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data.euNextAt != null
                    ? 'Hentet fra Vegvesen — neste EU ${data.euNextAt!.day}.${data.euNextAt!.month}.${data.euNextAt!.year}'
                    : 'Hentet fra Vegvesen — $plate (år ${data.modelYear ?? '—'}, nyttelast ${data.payloadKg ?? '—'} kg)',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vegvesen: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _vegvesenLoading.remove(row));
        if (!silent) setState(() => _saving = false);
      }
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
        hasTransportLicense: widget.partner.hasTransportLicense,
        transportLicenseCount: widget.partner.transportLicenseCount,
        employeeCount: int.tryParse(_employees.text),
        auditStatus: widget.partner.auditStatus,
        auditPlate: widget.partner.auditPlate,
        brregSnapshot: p.brregSnapshot,
        lastMeetingAt: p.lastMeetingAt,
        nextMeetingAt: p.nextMeetingAt,
        lastAuditAt: p.lastAuditAt,
        nextAuditAt: p.nextAuditAt,
        isActive: p.isActive,
        routesOwnerOnly: _routesOwnerOnly,
        ecoDrivingCompleted: _ecoDrivingCompleted,
        ecoDrivingDeadline: _ecoDrivingDeadline,
        ecoDrivingCompletedAt: _ecoDrivingCompletedAt,
        createdAt: p.createdAt,
      );
      await PartnerService.updatePartner(p.id, updated);

      final vehicles = <PartnerVehicle>[];
      final seenUnits = <String>{};

      for (final row in _rows.where((r) => r.isRegOnly)) {
        final regRaw = row.reg.text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
        if (regRaw.length < 4) continue;
        final unit = MaviUnitCodes.registrationUnitCode(regRaw);
        if (unit.isEmpty || seenUnits.contains(unit)) continue;
        seenUnits.add(unit);
        vehicles.add(
          PartnerVehicle(
            id: row.id ?? '',
            partnerId: p.id,
            companyId: p.companyId,
            unitCode: unit,
            registrationNumber: regRaw,
            vehicleKind: 'registration',
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

      final pendingMavi = _rows.where((r) => !r.isRegOnly).toList();
      final emptyMavi = pendingMavi
          .where((r) => MaviUnitCodes.normalize(r.mavi.text).isEmpty)
          .toList();
      if (emptyMavi.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fyll inn MAVI-nummer på alle nye biler før lagring.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      for (final row in pendingMavi) {
        final unit = MaviUnitCodes.normalize(row.mavi.text);
        if (unit.isEmpty || seenUnits.contains(unit)) continue;
        seenUnits.add(unit);
        final regRaw = row.reg.text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
        final reg = regRaw.isEmpty ? MaviUnitCodes.regNrPlaceholder : regRaw;
        final driverName = row.driverName.text.trim();
        vehicles.add(
          PartnerVehicle(
            id: row.id ?? '',
            partnerId: p.id,
            companyId: p.companyId,
            unitCode: unit,
            registrationNumber: reg,
            vehicleKind: 'mavi',
            driverName: driverName.isEmpty ? null : driverName,
            phone: row.portalPhone.text.trim().isEmpty ? null : row.portalPhone.text.trim(),
            imageUrls: row.imagePaths,
            isActive: row.isActive,
            fleetRoles: MaviFleetRoles.normalize(row.fleetRoles),
            createdAt: DateTime.now(),
          ),
        );
      }
      final saved = await PartnerService.replaceVehicles(
        partnerId: p.id,
        companyId: p.companyId,
        vehicles: vehicles,
      );

      final savedMavi = saved
          .where((v) =>
              v.vehicleKind != 'registration' &&
              !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
          .length;
      final expectedMavi = vehicles.where((v) => v.vehicleKind == 'mavi').length;
      final expectedReg = vehicles.where((v) => v.vehicleKind == 'registration').length;
      final savedReg = saved
          .where((v) =>
              v.vehicleKind == 'registration' ||
              MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
          .length;
      if (savedMavi < expectedMavi) {
        throw StateError(
          'Kunne ikke lagre alle MAVI-biler ($savedMavi av $expectedMavi). '
          'Sjekk at nummeret er gyldig (f.eks. M75 eller NO_O_M0075).',
        );
      }
      if (savedReg < expectedReg) {
        throw StateError(
          'Kunne ikke lagre alle skiltnummer ($savedReg av $expectedReg). '
          'Sjekk at reg.nr har minst 4 tegn.',
        );
      }

      if (mounted) {
        _resetVehicles(saved);
        await _loadPortals();
        final parts = <String>[];
        if (savedReg > 0) parts.add('$savedReg reg.nr');
        if (savedMavi > 0) parts.add('$savedMavi MAVI');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              parts.isEmpty ? 'Lagret' : 'Lagret — ${parts.join(' · ')}',
            ),
          ),
        );
        await widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke lagre: ${_friendlyPartnerSaveError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.partner;
    final regRows = _rows.where((r) => r.isRegOnly).toList();
    final maviRows = _rows.where((r) => !r.isRegOnly).toList();
    final smsPhones = <String>{
      if (_phone.text.trim().isNotEmpty) _phone.text.trim(),
      ..._ownerRows.map((r) => r.phone.text.trim()).where((v) => v.isNotEmpty),
      ...maviRows.map((r) => r.portalPhone.text.trim()).where((v) => v.isNotEmpty),
    };
    final activeOwnerCount = _ownerRows.where((r) => r.hasPortalAccount).length;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
          children: [
            PartnerModernPageHeader(
              title: p.tradeName?.isNotEmpty == true ? p.tradeName! : p.name,
              subtitle: [
                if (p.orgNumber != null) 'Org.nr ${p.orgNumber}',
                if (p.ownerName?.isNotEmpty == true) p.ownerName!,
                '${maviRows.length} MAVI · ${regRows.length} reg.nr',
              ].join(' · '),
            ),
            if (maviRows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PartnerModernUi.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PartnerModernUi.border(context)),
                  ),
                  child: PartnerMaviVehicleOverview(
                    vehicles: PartnerMaviVehicleOverview.filterMavi(
                      maviRows
                          .map(
                            (r) => PartnerVehicle(
                              id: r.id ?? '',
                              partnerId: widget.partner.id,
                              companyId: widget.partner.companyId,
                              unitCode: MaviUnitCodes.normalize(r.mavi.text),
                              registrationNumber: r.reg.text.trim(),
                              driverName: r.driverName.text.trim().isEmpty
                                  ? null
                                  : r.driverName.text.trim(),
                              fleetRoles: r.fleetRoles.toList(),
                              isActive: r.isActive,
                              createdAt: DateTime.now(),
                            ),
                          )
                          .where((v) => v.unitCode.isNotEmpty)
                          .toList(),
                    ),
                    lastInspectionByVehicleId: _inspectionByVehicleId,
                  ),
                ),
              ),
            if (regRows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PartnerModernUi.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PartnerModernUi.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Registrerte skilt (${regRows.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: PartnerModernUi.textPrimary(context).withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: regRows.map((r) {
                          final plate = r.reg.text.trim().toUpperCase();
                          return Chip(
                            label: Text(
                              plate,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Skilt vises under Bilkontroll etter at du har trykket Lagre endringer.',
                        style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                      ),
                    ],
                  ),
                ),
              ),
            PartnerModernKpiGrid(
              items: [
                ('MAVI', '${maviRows.length}'),
                ('Reg.nr', '${regRows.length}'),
                ('SMS', '${smsPhones.length}'),
                ('Portal', activeOwnerCount == 0 ? 'Mangler' : '$activeOwnerCount'),
              ],
            ),
            const SizedBox(height: 8),
            PartnerModernSegmented<_OverviewSection>(
              options: _OverviewSection.values,
              selected: _activeSection,
              labelOf: (s) => s.label,
              onSelected: (s) => setState(() => _activeSection = s),
            ),
            const SizedBox(height: 8),
            if (_activeSection == _OverviewSection.profile)
              PartnerModernSection(
              title: 'Kommentar',
              subtitle: 'Intern notat',
              children: [
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Kommentar / notater',
                    hintText: 'F.eks. avtaler, spesielle forhold, kontaktperson …',
                  ),
                ),
              ],
            ),
            if (_activeSection == _OverviewSection.profile)
              PartnerModernSection(
              title: 'Kontakt & bedrift',
              subtitle: 'Org.nr ${p.orgNumber ?? "—"}',
              initiallyExpanded: true,
              children: [
                  _field('Bedriftsansvarlig', _owner),
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
              ],
            ),
            if (_activeSection == _OverviewSection.profile)
              PartnerModernSection(
              title: 'ECO Driving Kurs',
              subtitle: 'Grønn badge på bedriftskort når kurset er tatt',
              initiallyExpanded: true,
              children: [
                EcoDrivingCourseEditor(
                  completed: _ecoDrivingCompleted,
                  deadline: _ecoDrivingDeadline,
                  onCompletedChanged: (v) {
                    setState(() {
                      _ecoDrivingCompleted = v;
                      if (v) {
                        _ecoDrivingCompletedAt = DateTime.now();
                      } else {
                        _ecoDrivingCompletedAt = null;
                        _ecoDrivingDeadline ??=
                            Partner.defaultEcoDrivingDeadline();
                      }
                    });
                  },
                ),
              ],
            ),
            if (_activeSection == _OverviewSection.routing)
              PartnerModernSection(
              title: 'Ruter og varsler',
              subtitle: 'Styr hvem som mottar ruter fra DriftPro',
              initiallyExpanded: true,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Del ruter og godkjenning i portal (GDPR).',
                    style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                  ),
                ),
                Column(
                  children: [
                    RadioListTile<int>(
                      value: 1,
                      groupValue: _routesOwnerOnly ? 1 : 2,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kun bedriftsansvarlig', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('Sjåfører ser ikke ruter · bedriftsansvarlig håndterer ruter'),
                      onChanged: _routesOwnerOnlySaving ? null : (v) => _setRoutesOwnerOnly(true),
                    ),
                    RadioListTile<int>(
                      value: 2,
                      groupValue: _routesOwnerOnly ? 1 : 2,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bedriftsansvarlig og sjåfør', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('Sjåfører ser ruter for sin egen bil og kan godkjenne/avvise'),
                      onChanged: _routesOwnerOnlySaving ? null : (v) => _setRoutesOwnerOnly(false),
                    ),
                    RadioListTile<int>(
                      value: 3,
                      groupValue: _routesOwnerOnly ? 1 : 2,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sjåfører ser ruter, men kan ikke godkjenne'),
                      subtitle: const Text('Kommer snart: krever ny backend-styring for akseptrettigheter'),
                      enabled: false,
                      onChanged: null,
                    ),
                  ],
                ),
                if (_routesOwnerOnlySaving)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
            if (_activeSection == _OverviewSection.ownerPortal)
              PartnerModernSection(
              title: 'Portal for bedriftsansvarlig',
              subtitle:
                  'Auto-generert brukernavn og passord registreres i Supabase og sendes på SMS. '
                  'Bedriftsansvarlig får tilgang til dokumenter, møter og revisjon — ikke sjåfører. '
                  'Ved bytte av telefonnummer slettes gammel konto automatisk.',
              trailing: Text(
                '${_ownerRows.where((r) => r.hasPortalAccount).length}/${_ownerRows.length}',
                style: TextStyle(fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context)),
              ),
              children: [
                ..._ownerRows.map(_ownerPortalCard),
                OutlinedButton.icon(
                  onPressed: _portalSaving ? null : _addOwnerPortalRow,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Legg til bil-eier'),
                ),
              ],
            ),
            if (_activeSection == _OverviewSection.registrations)
              PartnerModernSection(
              title: 'Registrerte skiltnummer på dette firmaet',
              subtitle:
                  'Skiltnummer, årsmodell, nyttelast og EU-kontroll. '
                  'EU-dato hentes automatisk fra Vegvesen når du skriver skiltnummer.',
              trailing: Text('${regRows.length}', style: TextStyle(fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context))),
              children: [
                if (regRows.isEmpty)
                  PartnerEmptyState(
                    icon: Icons.add_road_outlined,
                    title: 'Ingen reg.nr registrert',
                    subtitle: 'Legg til alle registreringsnummer uavhengig av MAVI.',
                  )
                else
                  ...regRows.map(_regCard),
                OutlinedButton.icon(
                  onPressed: _addRegRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Legg til reg.nr'),
                ),
              ],
            ),
            if (_activeSection == _OverviewSection.maviDrivers)
              PartnerModernSection(
              title: 'MAVI & sjåfør',
              subtitle: 'Auto brukernavn · SMS ved opprettelse',
              initiallyExpanded: true,
              trailing: Text('${maviRows.length}', style: TextStyle(fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context))),
              children: [
                if (maviRows.isEmpty)
                  PartnerEmptyState(
                    icon: Icons.add_box_outlined,
                    title: 'Ingen MAVI-nummer ennå',
                    subtitle: 'Legg til MAVI og koble valgfritt til reg.nr fra listen over.',
                  )
                else
                  ...maviRows.map(_vehicleCard),
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
                        label: const Text('Lim inn flere'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        PartnerStickySaveBar(
          label: 'Lagre endringer',
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
        if (_saving) const ModalBarrier(dismissible: false),
      ],
    );
  }

  Widget _ownerPortalCard(_OwnerPortalRowState row) {
    final previewUsername = row.previewUsername(
      partnerName: widget.partner.name,
      orgNumber: widget.partner.orgNumber,
      partnerId: widget.partner.id,
    );
    final needsNewCredentials = !row.hasPortalAccount;
    final phoneChanged = row.pendingPhoneReplace || row.phoneChangedFromSaved();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(
          color: phoneChanged
              ? DriftProTheme.warning.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.hasPortalAccount ? 'Aktiv bil-eier' : 'Ny bil-eier',
                  style: DriftProTheme.headingSm.copyWith(fontSize: 13),
                ),
              ),
              if (_ownerRows.length > 1 || row.hasPortalAccount)
                IconButton(
                  tooltip: 'Fjern bil-eier',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _portalSaving ? null : () => _removeOwnerPortalRow(row),
                ),
            ],
          ),
          TextField(
            controller: row.displayName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Navn (valgfri)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Bedriftsansvarlig telefon (SMS) *',
              border: const OutlineInputBorder(),
              isDense: true,
              helperText: phoneChanged
                  ? 'Nummer endret — gammel konto er slettet. Send innlogging til det nye nummeret.'
                  : null,
            ),
            onChanged: (_) {
              setState(() {});
              _scheduleOwnerPhoneReplaceCheck(row);
            },
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DriftProTheme.accentBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
              border: Border.all(color: DriftProTheme.accentBlue.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto brukernavn', style: DriftProTheme.labelSm),
                Text(
                  previewUsername,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  row.hasPortalAccount && row.username != null
                      ? 'Aktiv brukernavn: ${row.username}'
                      : 'Passord genereres automatisk ved opprettelse og sendes på SMS.',
                  style: DriftProTheme.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (needsNewCredentials)
                FilledButton.icon(
                  onPressed: _portalSaving ? null : () => _saveOwnerPortal(row),
                  icon: const Icon(Icons.sms_outlined, size: 18),
                  label: Text(
                    phoneChanged ? 'Send innlogging til nytt nummer (SMS)' : 'Opprett bedriftsansvarlig (SMS)',
                  ),
                  style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                )
              else ...[
                FilledButton.icon(
                  onPressed: _portalSaving ? null : () => _resendOwnerPortalPassword(row),
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Send nytt passord (SMS)'),
                  style: FilledButton.styleFrom(backgroundColor: DriftProTheme.accentBlue),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _regCard(_VehicleRowState row) {
    Color? border;
    if (row.euNext != null && row.euNext!.isBefore(DateTime.now())) {
      border = DriftProTheme.error;
    } else if (row.euNext != null &&
        row.euNext!.isBefore(DateTime.now().add(const Duration(days: 60)))) {
      border = DriftProTheme.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: border != null ? border.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: border ?? Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.reg,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Registreringsnummer *',
                      hintText: 'AB12345',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _scheduleVegvesenLookup(row),
                  ),
                ),
                if (_vegvesenLoading.contains(row))
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Oppdater fra Vegvesen',
                    onPressed: () => _lookupVegvesen(row),
                    icon: const Icon(Icons.cloud_download_outlined),
                  ),
                IconButton(
                  tooltip: 'Fjern bil',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      row.reg.dispose();
                      row.driverName.dispose();
                      row.payload.dispose();
                      row.year.dispose();
                      row.portalPhone.dispose();
                      row.mavi.dispose();
                      _rows.remove(row);
                    });
                  },
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
                _vegvesenLoading.contains(row)
                    ? 'Henter fra Vegvesen …'
                    : row.euNext != null
                        ? '${row.euNext!.day}.${row.euNext!.month}.${row.euNext!.year}'
                        : 'Hentes automatisk når reg.nr er fylt ut',
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
          ],
        ),
    );
  }

  Widget _vehicleCard(_VehicleRowState row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.18)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: row.mavi,
                    onChanged: (_) => setState(() {}),
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
                      row.driverName.dispose();
                      row.payload.dispose();
                      row.year.dispose();
                      row.portalPhone.dispose();
                      _rows.remove(row);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                const Text('Biltype (kan velge flere):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ...MaviFleetRoles.all.map((role) {
                  final selected = row.fleetRoles.contains(role);
                  return FilterChip(
                    label: Text(MaviFleetRoles.label(role), style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: row.isActive
                        ? (v) => setState(() {
                              if (v) {
                                row.fleetRoles.add(role);
                              } else {
                                row.fleetRoles.remove(role);
                              }
                            })
                        : null,
                  );
                }),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktiv i ruteplanlegger', style: TextStyle(fontSize: 12)),
              subtitle: Text(
                row.isActive
                    ? 'Vises i kalender og kan få ruter'
                    : 'Deaktivert — skjules fra ruter og planlegging',
                style: const TextStyle(fontSize: 11),
              ),
              value: row.isActive,
              onChanged: (v) => setState(() => row.isActive = v),
            ),
            const SizedBox(height: 8),
            if (_registeredPlates.isNotEmpty && row.reg.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Koblet reg.nr (fra registrerte biler)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(
                    row.reg.text.trim().toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              )
            else if (_registeredPlates.isNotEmpty)
              DropdownButtonFormField<String>(
                value: () {
                  final p = row.reg.text.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
                  return _registeredPlates.contains(p) ? p : null;
                }(),
                decoration: const InputDecoration(
                  labelText: 'Koble MAVI til reg.nr (valgfritt)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— ingen kobling —')),
                  ..._registeredPlates.map(
                    (p) => DropdownMenuItem(value: p, child: Text(p)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    row.reg.text = v;
                    setState(() {});
                  }
                },
              ),
            const Divider(height: 16),
            Text('Sjåfør og innlogging', style: DriftProTheme.headingSm.copyWith(fontSize: 13)),
            TextField(
              controller: row.driverName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Sjåfør navn *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.portalPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Sjåfør telefon (SMS) *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto innlogging (genereres per MAVI)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.previewUsername.isEmpty
                        ? 'Fyll inn MAVI for å se brukernavn'
                        : 'Brukernavn: ${row.previewUsername}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  Text(
                    row.hasPortalAccount && row.generatedPasswordPreview != null
                        ? 'Passord (sist): ${row.generatedPasswordPreview}'
                        : 'Passord: genereres ved «Opprett sjåfør» og sendes på SMS',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              row.hasPortalAccount
                  ? 'Portal aktiv${row.portalUsername != null ? " · ${row.portalUsername}" : ""}'
                  : 'Trykk «Opprett sjåfør» for SMS med brukernavn og passord til samarbeidspartner-innlogging',
              style: TextStyle(
                fontSize: 11,
                color: row.hasPortalAccount ? Colors.green.shade700 : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!row.hasPortalAccount)
                  FilledButton.icon(
                    onPressed: _portalSaving ? null : () => _saveVehiclePortal(row),
                    icon: const Icon(Icons.sms_outlined, size: 18),
                    label: const Text('Opprett sjåfør (SMS)'),
                    style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                  )
                else if (_isSuperAdmin) ...[
                  FilledButton.icon(
                    onPressed: _portalSaving ? null : () => _resendDriverPortalPassword(row),
                    icon: const Icon(Icons.lock_reset, size: 18),
                    label: const Text('Send nytt passord (SMS)'),
                    style: FilledButton.styleFrom(backgroundColor: DriftProTheme.accentBlue),
                  ),
                  OutlinedButton(
                    onPressed: _portalSaving ? null : () => _deleteVehiclePortal(row),
                    child: const Text('Slett sjåfør'),
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
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => Chip(
                    label: Text('Bilde ${i + 1}', style: const TextStyle(fontSize: 10)),
                    onDeleted: () => setState(() => row.imagePaths.removeAt(i)),
                  ),
                ),
              ),
          ],
        ),
    );
  }
}
