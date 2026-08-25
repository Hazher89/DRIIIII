import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/services/sms/sms_phone_utils.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/bytes_download.dart';
import '../../../core/utils/portal_credentials.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'partner_modern_ui.dart';

enum _TimeRange { day, week, month, days90, year, archive }

/// MAVI/superadmin: ansatte, innlogging, timer og arkiv for én bedrift.
class PartnerWorkforceAdminPanel extends StatefulWidget {
  const PartnerWorkforceAdminPanel({
    super.key,
    required this.partner,
    required this.enabled,
    this.isSuperAdmin = false,
    this.onStaffCountChanged,
  });

  final Partner partner;
  final bool enabled;
  final bool isSuperAdmin;
  final ValueChanged<int>? onStaffCountChanged;

  @override
  State<PartnerWorkforceAdminPanel> createState() =>
      _PartnerWorkforceAdminPanelState();
}

class _PartnerWorkforceAdminPanelState extends State<PartnerWorkforceAdminPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PartnerStaff> _staff = [];
  Map<String, PartnerPortalAccount> _accountsById = {};
  List<PartnerTimeEntry> _entries = [];
  List<PartnerTimeAudit> _audits = [];
  Set<String> _clockedInStaffIds = {};
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _showInactive = true;
  String? _staffFilter;
  _TimeRange _range = _TimeRange.month;
  bool _showAudit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.enabled) _load();
  }

  @override
  void didUpdateWidget(covariant PartnerWorkforceAdminPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        _load();
      } else {
        setState(() {
          _staff = [];
          _entries = [];
          _loading = false;
        });
        widget.onStaffCountChanged?.call(0);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) _rangeBounds() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_range) {
      case _TimeRange.day:
        final start = DateTime(now.year, now.month, now.day);
        return (start, end);
      case _TimeRange.week:
        final weekday = now.weekday;
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        return (start, end);
      case _TimeRange.month:
        return (DateTime(now.year, now.month, 1), end);
      case _TimeRange.days90:
        return (now.subtract(const Duration(days: 90)), end);
      case _TimeRange.year:
        return (DateTime(now.year, 1, 1), end);
      case _TimeRange.archive:
        return (DateTime(now.year - 5, 1, 1), end);
    }
  }

  Future<void> _load() async {
    if (!widget.enabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = _rangeBounds();
      final results = await Future.wait([
        PartnerWorkforceService.listStaff(
          partnerId: widget.partner.id,
          includeInactive: true,
        ),
        PartnerService.fetchPortalAccounts(widget.partner.id),
        PartnerWorkforceService.listEntries(
          partnerId: widget.partner.id,
          from: from,
          to: to?.add(const Duration(days: 1)),
          staffId: _staffFilter,
        ),
        PartnerWorkforceService.listAudits(partnerId: widget.partner.id),
      ]);
      final staff = results[0] as List<PartnerStaff>;
      final accounts = results[1] as List<PartnerPortalAccount>;
      final entries = results[2] as List<PartnerTimeEntry>;
      final audits = results[3] as List<PartnerTimeAudit>;
      final byId = <String, PartnerPortalAccount>{};
      for (final a in accounts) {
        if (a.accountKind == 'staff') byId[a.id] = a;
      }
      final clockedIn = entries
          .where((e) => e.isOpen)
          .map((e) => e.staffId)
          .toSet();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _accountsById = byId;
        _entries = entries;
        _audits = audits;
        _clockedInStaffIds = clockedIn;
        _loading = false;
      });
      widget.onStaffCountChanged?.call(staff.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
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

  List<PartnerStaff> get _filteredStaff {
    final q = _query.trim().toLowerCase();
    return _staff.where((s) {
      if (!_showInactive && !s.isActive) return false;
      if (q.isEmpty) return true;
      final username = _usernameFor(s)?.toLowerCase() ?? '';
      return s.fullName.toLowerCase().contains(q) ||
          (s.phone?.contains(q) ?? false) ||
          username.contains(q);
    }).toList();
  }

  Map<String, List<PartnerTimeEntry>> get _entriesByStaff {
    final map = <String, List<PartnerTimeEntry>>{};
    for (final e in _entries) {
      map.putIfAbsent(e.staffId, () => []).add(e);
    }
    return map;
  }

  double _hoursForStaff(String staffId) {
    var m = 0;
    for (final e in _entries.where((x) => x.staffId == staffId)) {
      if (e.isOpen) {
        m += DateTime.now().difference(e.clockIn).inMinutes;
      } else {
        m += e.duration?.inMinutes ?? 0;
      }
    }
    return m / 60.0;
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
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
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
          content: Text('Sett gyldig mobil først'),
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
          'Det gamle slutter å virke med én gang.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lag nytt passord'),
          ),
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

  Future<void> _exportExcel() async {
    final bytes = PartnerWorkforceService.buildExcelBytes(
      partnerName: widget.partner.name,
      entries: _entries,
    );
    final name =
        'timer_${widget.partner.name.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    await downloadBytes(
      Uint8List.fromList(bytes),
      name,
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Excel lastet ned')),
    );
  }

  Future<void> _editEntry(PartnerTimeEntry e) async {
    final me = await SupabaseService.fetchEffectiveUserProfile();
    if (me == null) return;
    var inAt = e.clockIn.toLocal();
    var outAt = e.clockOut?.toLocal();
    final noteCtrl = TextEditingController(text: e.note ?? '');
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    Future<DateTime?> pick(BuildContext ctx, DateTime initial) async {
      final d = await showDatePicker(
        context: ctx,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (d == null) return null;
      if (!ctx.mounted) return null;
      final t = await showTimePicker(
        context: ctx,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (t == null) return null;
      return DateTime(d.year, d.month, d.day, t.hour, t.minute);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Rediger — ${e.staffName ?? 'ansatt'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inn'),
                  subtitle: Text(fmt.format(inAt)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await pick(ctx, inAt);
                    if (v != null) setLocal(() => inAt = v);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ut'),
                  subtitle: Text(outAt == null ? 'Åpen (på jobb)' : fmt.format(outAt!)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await pick(ctx, outAt ?? inAt);
                    if (v != null) setLocal(() => outAt = v);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Merknad',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
          ],
        ),
      ),
    );
    if (ok != true) {
      noteCtrl.dispose();
      return;
    }
    try {
      await PartnerWorkforceService.upsertManualEntry(
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        staffId: e.staffId,
        clockIn: inAt,
        clockOut: outAt,
        note: noteCtrl.text,
        entryId: e.id,
        editorId: me.id,
        isAdmin: widget.isSuperAdmin || me.isAdmin,
      );
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err'), backgroundColor: DriftProTheme.error),
      );
    } finally {
      noteCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Slå på funksjonen over for å administrere ansatte og timer.',
          style: TextStyle(fontSize: 13, color: PartnerModernUi.muted(context)),
        ),
      );
    }

    if (_loading && _staff.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: DriftProLoadingCenter(),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
      );
    }

    final active = _staff.where((s) => s.isActive).length;
    final withLogin = _staff.where((s) => s.profileId != null).length;
    final onJob = _clockedInStaffIds.length;
    final dayFmt = DateFormat('EEE d. MMM', 'nb');
    final timeFmt = DateFormat('HH:mm');
    final auditFmt = DateFormat('dd.MM.yyyy HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StatChip(label: 'Ansatte', value: '${_staff.length}', color: Colors.blueGrey),
            const SizedBox(width: 8),
            _StatChip(label: 'Aktive', value: '$active', color: DriftProTheme.primaryGreen),
            const SizedBox(width: 8),
            _StatChip(label: 'Innlogging', value: '$withLogin', color: const Color(0xFF1565C0)),
            const SizedBox(width: 8),
            _StatChip(
              label: 'På jobb nå',
              value: '$onJob',
              color: onJob > 0 ? Colors.orange.shade800 : Colors.blueGrey,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabController,
          labelColor: DriftProTheme.primaryGreen,
          unselectedLabelColor: PartnerModernUi.muted(context),
          indicatorColor: DriftProTheme.primaryGreen,
          tabs: const [
            Tab(text: 'Ansatte & innlogging'),
            Tab(text: 'Timer & arkiv'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 520,
          child: TabBarView(
            controller: _tabController,
            children: [
              _StaffTab(
                query: _query,
                showInactive: _showInactive,
                staff: _filteredStaff,
                usernameFor: _usernameFor,
                clockedInIds: _clockedInStaffIds,
                onQueryChanged: (v) => setState(() => _query = v),
                onShowInactiveChanged: (v) => setState(() => _showInactive = v),
                onRefresh: _load,
                onAdd: _addStaff,
                onProvision: _provision,
                onResetPassword: _resetPassword,
              ),
              _TimesTab(
                range: _range,
                staff: _staff,
                staffFilter: _staffFilter,
                entries: _entries,
                entriesByStaff: _entriesByStaff,
                showAudit: _showAudit,
                audits: _audits,
                hoursForStaff: _hoursForStaff,
                dayFmt: dayFmt,
                timeFmt: timeFmt,
                auditFmt: auditFmt,
                onRangeChanged: (r) {
                  setState(() => _range = r);
                  _load();
                },
                onStaffFilterChanged: (id) {
                  setState(() => _staffFilter = id);
                  _load();
                },
                onToggleAudit: () => setState(() => _showAudit = !_showAudit),
                onRefresh: _load,
                onExport: _entries.isEmpty ? null : _exportExcel,
                onEditEntry: _editEntry,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
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
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.query,
    required this.showInactive,
    required this.staff,
    required this.usernameFor,
    required this.clockedInIds,
    required this.onQueryChanged,
    required this.onShowInactiveChanged,
    required this.onRefresh,
    required this.onAdd,
    required this.onProvision,
    required this.onResetPassword,
  });

  final String query;
  final bool showInactive;
  final List<PartnerStaff> staff;
  final String? Function(PartnerStaff) usernameFor;
  final Set<String> clockedInIds;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onShowInactiveChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final Future<void> Function(PartnerStaff) onProvision;
  final Future<void> Function(PartnerStaff) onResetPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Søk navn, telefon, brukernavn…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
                onChanged: onQueryChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Oppdater', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Ny'),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vis deaktiverte', style: TextStyle(fontSize: 13)),
          value: showInactive,
          onChanged: onShowInactiveChanged,
        ),
        Expanded(
          child: staff.isEmpty
              ? Center(
                  child: Text(
                    'Ingen ansatte — trykk «Ny» for å registrere',
                    style: TextStyle(color: PartnerModernUi.muted(context)),
                  ),
                )
              : ListView.separated(
                  itemCount: staff.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final s = staff[i];
                    final username = usernameFor(s);
                    final onJob = clockedInIds.contains(s.id);
                    return _StaffRow(
                      staff: s,
                      username: username,
                      onJob: onJob,
                      onProvision: () => onProvision(s),
                      onResetPassword: () => onResetPassword(s),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.staff,
    required this.username,
    required this.onJob,
    required this.onProvision,
    required this.onResetPassword,
  });

  final PartnerStaff staff;
  final String? username;
  final bool onJob;
  final VoidCallback onProvision;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: onJob
              ? Colors.orange.withValues(alpha: 0.4)
              : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  staff.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              if (onJob)
                _Badge('På jobb', Colors.orange.shade800)
              else if (!staff.isActive)
                _Badge('Deaktivert', Colors.red.shade700)
              else if (username != null)
                _Badge('Innlogget klar', DriftProTheme.primaryGreen),
            ],
          ),
          if (staff.phone != null && staff.phone!.isNotEmpty)
            Text(staff.phone!, style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context))),
          if (username != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              'Brukernavn: $username',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (username == null)
                OutlinedButton.icon(
                  onPressed: onProvision,
                  icon: const Icon(Icons.vpn_key_outlined, size: 16),
                  label: const Text('Lag bruker'),
                )
              else
                OutlinedButton.icon(
                  onPressed: onResetPassword,
                  icon: const Icon(Icons.lock_reset, size: 16),
                  label: const Text('Nytt passord'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _TimesTab extends StatelessWidget {
  const _TimesTab({
    required this.range,
    required this.staff,
    required this.staffFilter,
    required this.entries,
    required this.entriesByStaff,
    required this.showAudit,
    required this.audits,
    required this.hoursForStaff,
    required this.dayFmt,
    required this.timeFmt,
    required this.auditFmt,
    required this.onRangeChanged,
    required this.onStaffFilterChanged,
    required this.onToggleAudit,
    required this.onRefresh,
    required this.onExport,
    required this.onEditEntry,
  });

  final _TimeRange range;
  final List<PartnerStaff> staff;
  final String? staffFilter;
  final List<PartnerTimeEntry> entries;
  final Map<String, List<PartnerTimeEntry>> entriesByStaff;
  final bool showAudit;
  final List<PartnerTimeAudit> audits;
  final double Function(String) hoursForStaff;
  final DateFormat dayFmt;
  final DateFormat timeFmt;
  final DateFormat auditFmt;
  final ValueChanged<_TimeRange> onRangeChanged;
  final ValueChanged<String?> onStaffFilterChanged;
  final VoidCallback onToggleAudit;
  final Future<void> Function() onRefresh;
  final VoidCallback? onExport;
  final Future<void> Function(PartnerTimeEntry) onEditEntry;

  @override
  Widget build(BuildContext context) {
    final totalHours = entries.fold<double>(0, (sum, e) {
      if (e.isOpen) {
        return sum + DateTime.now().difference(e.clockIn).inMinutes / 60.0;
      }
      return sum + (e.duration?.inMinutes ?? 0) / 60.0;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${totalHours.toStringAsFixed(1)} t · ${entries.length} poster',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(
              tooltip: showAudit ? 'Skjul logg' : 'Endringslogg',
              onPressed: onToggleAudit,
              icon: Icon(Icons.history, color: showAudit ? DriftProTheme.primaryGreen : null),
            ),
            IconButton(tooltip: 'Oppdater', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
            if (onExport != null)
              FilledButton.tonalIcon(
                onPressed: onExport,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Excel'),
              ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in _TimeRange.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_rangeLabel(r)),
                    selected: range == r,
                    onSelected: (_) => onRangeChanged(r),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          // ignore: deprecated_member_use
          value: staffFilter,
          decoration: const InputDecoration(
            labelText: 'Filtrer ansatt',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Alle ansatte')),
            ...staff.map(
              (s) => DropdownMenuItem(value: s.id, child: Text(s.fullName)),
            ),
          ],
          onChanged: onStaffFilterChanged,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: showAudit
              ? ListView.separated(
                  itemCount: audits.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) {
                    final a = audits[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_note, size: 20),
                      title: Text('${a.action} · ${a.changedByName ?? 'ukjent'}'),
                      subtitle: Text(
                        auditFmt.format(a.changedAt.toLocal()),
                        style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                      ),
                    );
                  },
                )
              : entriesByStaff.isEmpty
                  ? Center(
                      child: Text(
                        'Ingen timer i valgt periode',
                        style: TextStyle(color: PartnerModernUi.muted(context)),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final s in staff.where((x) => entriesByStaff.containsKey(x.id)))
                          _StaffHoursBlock(
                            staff: s,
                            hours: hoursForStaff(s.id),
                            entries: entriesByStaff[s.id]!,
                            dayFmt: dayFmt,
                            timeFmt: timeFmt,
                            onEditEntry: onEditEntry,
                          ),
                      ],
                    ),
        ),
      ],
    );
  }

  String _rangeLabel(_TimeRange r) => switch (r) {
        _TimeRange.day => 'I dag',
        _TimeRange.week => 'Uke',
        _TimeRange.month => 'Mnd',
        _TimeRange.days90 => '90 d',
        _TimeRange.year => '1 år',
        _TimeRange.archive => '5 år',
      };
}

class _StaffHoursBlock extends StatelessWidget {
  const _StaffHoursBlock({
    required this.staff,
    required this.hours,
    required this.entries,
    required this.dayFmt,
    required this.timeFmt,
    required this.onEditEntry,
  });

  final PartnerStaff staff;
  final double hours;
  final List<PartnerTimeEntry> entries;
  final DateFormat dayFmt;
  final DateFormat timeFmt;
  final Future<void> Function(PartnerTimeEntry) onEditEntry;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(staff.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${hours.toStringAsFixed(1)} timer · ${entries.length} poster'),
      children: entries.map((e) {
        final dur = e.isOpen
            ? PartnerWorkforceService.formatDurationClock(
                DateTime.now().difference(e.clockIn),
              )
            : PartnerWorkforceService.formatDurationClock(e.duration ?? Duration.zero);
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 8, right: 0),
          leading: Icon(
            e.isOpen ? Icons.timelapse : Icons.check_circle_outline,
            color: e.isOpen ? Colors.orange.shade800 : DriftProTheme.primaryGreen,
            size: 20,
          ),
          title: Text(dayFmt.format(e.clockIn.toLocal())),
          subtitle: Text(
            '${timeFmt.format(e.clockIn.toLocal())} – '
            '${e.clockOut == null ? 'på jobb' : timeFmt.format(e.clockOut!.toLocal())} · $dur',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => onEditEntry(e),
          ),
        );
      }).toList(),
    );
  }
}
