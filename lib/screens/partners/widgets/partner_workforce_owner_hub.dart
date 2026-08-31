import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/bytes_download.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'partner_modern_ui.dart';

enum PartnerWorkforceTimeRange { day, week, month, days90, year }

(DateTime?, DateTime?) partnerWorkforceRangeBounds(PartnerWorkforceTimeRange range) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  switch (range) {
    case PartnerWorkforceTimeRange.day:
      return (DateTime(now.year, now.month, now.day), end);
    case PartnerWorkforceTimeRange.week:
      final weekday = now.weekday;
      final start =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
      return (start, end);
    case PartnerWorkforceTimeRange.month:
      return (DateTime(now.year, now.month, 1), end);
    case PartnerWorkforceTimeRange.days90:
      return (now.subtract(const Duration(days: 90)), end);
    case PartnerWorkforceTimeRange.year:
      return (DateTime(now.year, 1, 1), end);
  }
}

String partnerWorkforceRangeLabel(PartnerWorkforceTimeRange range) => switch (range) {
      PartnerWorkforceTimeRange.day => 'I dag',
      PartnerWorkforceTimeRange.week => 'Uke',
      PartnerWorkforceTimeRange.month => 'Mnd',
      PartnerWorkforceTimeRange.days90 => '90 d',
      PartnerWorkforceTimeRange.year => '1 år',
    };

/// Bil-eier: full timeliste/tidsbank — oversikt, grupperte timer, logg og Excel.
class PartnerWorkforceOwnerHubController {
  Future<void> Function()? _addManualEntry;

  Future<void> addManualEntry() async {
    await _addManualEntry?.call();
  }
}

class PartnerWorkforceOwnerHub extends StatefulWidget {
  const PartnerWorkforceOwnerHub({
    super.key,
    required this.partner,
    this.isSuperAdmin = false,
    this.controller,
  });

  final Partner partner;
  final bool isSuperAdmin;
  final PartnerWorkforceOwnerHubController? controller;

  @override
  State<PartnerWorkforceOwnerHub> createState() => _PartnerWorkforceOwnerHubState();
}

class _PartnerWorkforceOwnerHubState extends State<PartnerWorkforceOwnerHub>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  RealtimeChannel? _entriesChannel;

  List<PartnerStaff> _staff = [];
  List<PartnerTimeEntry> _entries = [];
  List<PartnerTimeAudit> _audits = [];
  bool _loading = true;
  String? _error;
  String? _staffFilter;
  PartnerWorkforceTimeRange _range = PartnerWorkforceTimeRange.month;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.controller?._addManualEntry = _addManualEntry;
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (widget.controller?._addManualEntry == _addManualEntry) {
      widget.controller?._addManualEntry = null;
    }
    unawaited(_entriesChannel?.unsubscribe() ?? Future.value());
    _tabController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    final pid = widget.partner.id;
    _entriesChannel = Supabase.instance.client
        .channel('owner_workforce_entries_$pid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'partner_time_entries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'partner_id',
            value: pid,
          ),
          callback: (_) => unawaited(_load(silent: true)),
        )
        .subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final (from, to) = partnerWorkforceRangeBounds(_range);
      final results = await Future.wait([
        PartnerWorkforceService.listStaff(
          partnerId: widget.partner.id,
          includeInactive: true,
        ),
        PartnerWorkforceService.listEntries(
          partnerId: widget.partner.id,
          from: from,
          to: to?.add(const Duration(days: 1)),
          staffId: _staffFilter,
        ),
        PartnerWorkforceService.listAudits(partnerId: widget.partner.id),
      ]);
      if (!mounted) return;
      setState(() {
        _staff = results[0] as List<PartnerStaff>;
        _entries = results[1] as List<PartnerTimeEntry>;
        _audits = results[2] as List<PartnerTimeAudit>;
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

  Map<String, List<PartnerTimeEntry>> get _entriesByStaff =>
      PartnerWorkforceService.groupByStaff(_entries);

  Set<String> get _clockedInStaffIds => PartnerWorkforceService.openStaffIds(_entries);

  double _hoursForStaff(String staffId) =>
      PartnerWorkforceService.totalHours(_entriesByStaff[staffId] ?? const []);

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

  Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime initial) async {
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

  Future<void> _editEntry(PartnerTimeEntry e, {bool allowDelete = true}) async {
    final me = await SupabaseService.fetchEffectiveUserProfile();
    if (me == null) return;
    var inAt = e.clockIn.toLocal();
    var outAt = e.clockOut?.toLocal();
    final noteCtrl = TextEditingController(text: e.note ?? '');
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    final ok = await showDialog<String>(
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
                  leading: const Icon(Icons.login_rounded, color: DriftProTheme.primaryGreen),
                  title: const Text('Inn'),
                  subtitle: Text(fmt.format(inAt)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await _pickDateTime(ctx, inAt);
                    if (v != null) setLocal(() => inAt = v);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded, color: Colors.red.shade700),
                  title: const Text('Ut'),
                  subtitle: Text(outAt == null ? 'Åpen (på jobb)' : fmt.format(outAt!)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await _pickDateTime(ctx, outAt ?? inAt);
                    if (v != null) setLocal(() => outAt = v);
                  },
                ),
                if (outAt != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setLocal(() => outAt = null),
                      child: const Text('Sett som åpen (fjern ut)'),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Merknad / begrunnelse',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Endringen loggføres med hvem, når og fra→til.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          actions: [
            if (allowDelete)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                style: TextButton.styleFrom(foregroundColor: DriftProTheme.error),
                child: const Text('Slett'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Lagre')),
          ],
        ),
      ),
    );

    if (ok == 'delete') {
      noteCtrl.dispose();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Slett timeregistrering?'),
          content: const Text('Posten skjules fra listen, men ligger i endringsloggen.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
              child: const Text('Slett'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        try {
          await PartnerWorkforceService.softDeleteEntry(entryId: e.id, editorId: me.id);
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Timeregistrering slettet')),
          );
        } catch (err) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$err'), backgroundColor: DriftProTheme.error),
          );
        }
      }
      return;
    }

    if (ok != 'save') {
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timeregistrering oppdatert')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err'), backgroundColor: DriftProTheme.error),
      );
    } finally {
      noteCtrl.dispose();
    }
  }

  Future<void> _addManualEntry() async {
    final me = await SupabaseService.fetchEffectiveUserProfile();
    if (me == null) return;
    final activeStaff = _staff.where((s) => s.isActive).toList();
    if (activeStaff.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen aktive ansatte — registrer ansatt først')),
      );
      return;
    }

    var staffId = activeStaff.first.id;
    final now = DateTime.now();
    var inAt = DateTime(now.year, now.month, now.day, 8, 0);
    var outAt = DateTime(now.year, now.month, now.day, 16, 0);
    final noteCtrl = TextEditingController();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Legg til timer manuelt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: staffId,
                  decoration: const InputDecoration(
                    labelText: 'Ansatt',
                    border: OutlineInputBorder(),
                  ),
                  items: activeStaff
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.fullName)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => staffId = v);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Inn'),
                  subtitle: Text(fmt.format(inAt)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await _pickDateTime(ctx, inAt);
                    if (v != null) setLocal(() => inAt = v);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ut (valgfritt)'),
                  subtitle: Text(fmt.format(outAt)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await _pickDateTime(ctx, outAt);
                    if (v != null) setLocal(() => outAt = v);
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setLocal(() => outAt = inAt),
                    child: const Text('Fjern ut (åpen stempling)'),
                  ),
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
        staffId: staffId,
        clockIn: inAt,
        clockOut: outAt.isAfter(inAt) ? outAt : null,
        note: noteCtrl.text,
        entryId: null,
        editorId: me.id,
        isAdmin: widget.isSuperAdmin || me.isAdmin,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timeregistrering lagt til')),
      );
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
    if (_loading && _staff.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: DriftProLoadingCenter(),
      );
    }

    if (_error != null && _staff.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Prøv igjen'),
            ),
          ],
        ),
      );
    }

    final totalHours = PartnerWorkforceService.totalHours(_entries);
    final onJob = _clockedInStaffIds.length;
    final activeStaff = _staff.where((s) => s.isActive).length;
    final dayFmt = DateFormat('EEE d. MMM', 'nb');
    final timeFmt = DateFormat('HH:mm');
    final auditFmt = DateFormat('dd.MM.yyyy HH:mm');
    final openEntries = PartnerWorkforceService.openEntries(_entries);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StatChip(label: 'Timer', value: totalHours.toStringAsFixed(1), color: DriftProTheme.primaryGreen),
            const SizedBox(width: 8),
            _StatChip(label: 'Poster', value: '${_entries.length}', color: Colors.blueGrey),
            const SizedBox(width: 8),
            _StatChip(
              label: 'På jobb nå',
              value: '$onJob',
              color: onJob > 0 ? Colors.orange.shade800 : Colors.blueGrey,
            ),
            const SizedBox(width: 8),
            _StatChip(label: 'Aktive', value: '$activeStaff', color: const Color(0xFF1565C0)),
          ],
        ),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabController,
          labelColor: DriftProTheme.primaryGreen,
          unselectedLabelColor: PartnerModernUi.muted(context),
          indicatorColor: DriftProTheme.primaryGreen,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Timeliste'),
            Tab(text: 'Endringslogg'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OverviewTab(
                openEntries: openEntries,
                staff: _staff,
                entriesByStaff: _entriesByStaff,
                hoursForStaff: _hoursForStaff,
                dayFmt: dayFmt,
                timeFmt: timeFmt,
                onEditEntry: _editEntry,
                onGoToTimesheet: () => _tabController.animateTo(1),
              ),
              _TimesheetTab(
                range: _range,
                staff: _staff,
                staffFilter: _staffFilter,
                entries: _entries,
                entriesByStaff: _entriesByStaff,
                hoursForStaff: _hoursForStaff,
                dayFmt: dayFmt,
                timeFmt: timeFmt,
                onRangeChanged: (r) {
                  setState(() => _range = r);
                  _load();
                },
                onStaffFilterChanged: (id) {
                  setState(() => _staffFilter = id);
                  _load();
                },
                onRefresh: _load,
                onExport: _entries.isEmpty ? null : _exportExcel,
                onEditEntry: _editEntry,
              ),
              _AuditTab(audits: _audits, auditFmt: auditFmt, onRefresh: _load),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: body,
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.openEntries,
    required this.staff,
    required this.entriesByStaff,
    required this.hoursForStaff,
    required this.dayFmt,
    required this.timeFmt,
    required this.onEditEntry,
    required this.onGoToTimesheet,
  });

  final List<PartnerTimeEntry> openEntries;
  final List<PartnerStaff> staff;
  final Map<String, List<PartnerTimeEntry>> entriesByStaff;
  final double Function(String) hoursForStaff;
  final DateFormat dayFmt;
  final DateFormat timeFmt;
  final Future<void> Function(PartnerTimeEntry) onEditEntry;
  final VoidCallback onGoToTimesheet;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerModernUi.muted(context);
    final ranked = staff
        .where((s) => entriesByStaff.containsKey(s.id))
        .toList()
      ..sort((a, b) => hoursForStaff(b.id).compareTo(hoursForStaff(a.id)));

    return ListView(
      children: [
        if (openEntries.isNotEmpty) ...[
          Text('På jobb nå', style: TextStyle(fontWeight: FontWeight.w800, color: muted)),
          const SizedBox(height: 8),
          ...openEntries.map((e) {
            final elapsed = PartnerWorkforceService.formatDurationClock(
              DateTime.now().difference(e.clockIn),
            );
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: Colors.orange.shade50,
              child: ListTile(
                leading: Icon(Icons.timelapse_rounded, color: Colors.orange.shade800),
                title: Text(e.staffName ?? 'Ansatt', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  'Inn ${timeFmt.format(e.clockIn.toLocal())} · $elapsed',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => onEditEntry(e),
                ),
                onTap: () => onEditEntry(e),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                'Timer per ansatt',
                style: TextStyle(fontWeight: FontWeight.w800, color: muted),
              ),
            ),
            TextButton(onPressed: onGoToTimesheet, child: const Text('Full timeliste →')),
          ],
        ),
        const SizedBox(height: 8),
        if (ranked.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('Ingen timer i valgt periode', style: TextStyle(color: muted)),
            ),
          )
        else
          ...ranked.map((s) {
            final hours = hoursForStaff(s.id);
            final posts = entriesByStaff[s.id]!.length;
            final onJob = entriesByStaff[s.id]!.any((e) => e.isOpen);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (onJob ? Colors.orange : DriftProTheme.primaryGreen)
                      .withValues(alpha: 0.15),
                  child: Icon(
                    onJob ? Icons.timelapse : Icons.person,
                    color: onJob ? Colors.orange.shade800 : DriftProTheme.primaryGreen,
                    size: 20,
                  ),
                ),
                title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('$posts poster · ${dayFmt.format(DateTime.now())}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${hours.toStringAsFixed(1)} t',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: onJob ? Colors.orange.shade800 : DriftProTheme.primaryGreen,
                      ),
                    ),
                    if (onJob)
                      Text(
                        'På jobb',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange.shade800),
                      ),
                  ],
                ),
                onTap: onGoToTimesheet,
              ),
            );
          }),
      ],
    );
  }
}

class _TimesheetTab extends StatelessWidget {
  const _TimesheetTab({
    required this.range,
    required this.staff,
    required this.staffFilter,
    required this.entries,
    required this.entriesByStaff,
    required this.hoursForStaff,
    required this.dayFmt,
    required this.timeFmt,
    required this.onRangeChanged,
    required this.onStaffFilterChanged,
    required this.onRefresh,
    required this.onExport,
    required this.onEditEntry,
  });

  final PartnerWorkforceTimeRange range;
  final List<PartnerStaff> staff;
  final String? staffFilter;
  final List<PartnerTimeEntry> entries;
  final Map<String, List<PartnerTimeEntry>> entriesByStaff;
  final double Function(String) hoursForStaff;
  final DateFormat dayFmt;
  final DateFormat timeFmt;
  final ValueChanged<PartnerWorkforceTimeRange> onRangeChanged;
  final ValueChanged<String?> onStaffFilterChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback? onExport;
  final Future<void> Function(PartnerTimeEntry) onEditEntry;

  @override
  Widget build(BuildContext context) {
    final totalHours = PartnerWorkforceService.totalHours(entries);

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
              for (final r in PartnerWorkforceTimeRange.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(partnerWorkforceRangeLabel(r)),
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
            ...staff.map((s) => DropdownMenuItem(value: s.id, child: Text(s.fullName))),
          ],
          onChanged: onStaffFilterChanged,
        ),
        const SizedBox(height: 8),
        Text(
          'Gruppert per ansatt — trykk for å redigere eller slette',
          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: entriesByStaff.isEmpty
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
    final onJob = entries.any((e) => e.isOpen);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: onJob,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: (onJob ? Colors.orange : DriftProTheme.primaryGreen).withValues(alpha: 0.12),
          child: Icon(
            onJob ? Icons.timelapse : Icons.schedule,
            size: 18,
            color: onJob ? Colors.orange.shade800 : DriftProTheme.primaryGreen,
          ),
        ),
        title: Text(staff.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${hours.toStringAsFixed(1)} timer · ${entries.length} poster'
          '${onJob ? ' · på jobb nå' : ''}',
        ),
        children: entries.map((e) {
          final dur = e.isOpen
              ? PartnerWorkforceService.formatDurationClock(
                  DateTime.now().difference(e.clockIn),
                )
              : PartnerWorkforceService.formatDurationClock(e.duration ?? Duration.zero);
          return ListTile(
            dense: true,
            leading: Icon(
              e.isOpen ? Icons.timelapse : Icons.check_circle_outline,
              color: e.isOpen ? Colors.orange.shade800 : DriftProTheme.primaryGreen,
              size: 20,
            ),
            title: Text(dayFmt.format(e.clockIn.toLocal())),
            subtitle: Text(
              '${timeFmt.format(e.clockIn.toLocal())} – '
              '${e.clockOut == null ? 'på jobb' : timeFmt.format(e.clockOut!.toLocal())} · $dur'
              '${e.note != null && e.note!.trim().isNotEmpty ? '\n${e.note}' : ''}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => onEditEntry(e),
            ),
            onTap: () => onEditEntry(e),
          );
        }).toList(),
      ),
    );
  }
}

class _AuditTab extends StatelessWidget {
  const _AuditTab({
    required this.audits,
    required this.auditFmt,
    required this.onRefresh,
  });

  final List<PartnerTimeAudit> audits;
  final DateFormat auditFmt;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (audits.isEmpty) {
      return Center(
        child: Text(
          'Ingen endringer loggført ennå',
          style: TextStyle(color: PartnerModernUi.muted(context)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('${audits.length} hendelser', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(tooltip: 'Oppdater', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        Expanded(
          child: ListView.separated(
            itemCount: audits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final a = audits[i];
              return _AuditCard(audit: a, auditFmt: auditFmt);
            },
          ),
        ),
      ],
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.audit, required this.auditFmt});

  final PartnerTimeAudit audit;
  final DateFormat auditFmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: const Icon(Icons.edit_note, size: 22),
        title: Text(
          '${audit.action} · ${audit.changedByName ?? 'ukjent'}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          auditFmt.format(audit.changedAt.toLocal()),
          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
        ),
        children: [
          if (audit.reason != null && audit.reason!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Begrunnelse: ${audit.reason}'),
              ),
            ),
          if (audit.beforeJson != null)
            _JsonBlock(label: 'Før', data: audit.beforeJson!),
          if (audit.afterJson != null)
            _JsonBlock(label: 'Etter', data: audit.afterJson!),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.label, required this.data});

  final String label;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    for (final key in ['clock_in', 'clock_out', 'note', 'source']) {
      if (data.containsKey(key) && data[key] != null) {
        var v = data[key].toString();
        if (key.contains('clock')) {
          try {
            v = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(v).toLocal());
          } catch (_) {}
        }
        lines.add('$key: $v');
      }
    }
    if (lines.isEmpty) {
      lines.add(data.toString());
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$label:\n${lines.join('\n')}',
          style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: PartnerModernUi.muted(context)),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});

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
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
          ],
        ),
      ),
    );
  }
}
