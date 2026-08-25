import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/bytes_download.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';

class OwnerPortalTimesheetPage extends StatefulWidget {
  final Partner partner;
  final bool isSuperAdmin;

  const OwnerPortalTimesheetPage({
    super.key,
    required this.partner,
    this.isSuperAdmin = false,
  });

  @override
  State<OwnerPortalTimesheetPage> createState() =>
      _OwnerPortalTimesheetPageState();
}

class _OwnerPortalTimesheetPageState extends State<OwnerPortalTimesheetPage> {
  List<PartnerTimeEntry> _entries = [];
  List<PartnerStaff> _staff = [];
  List<PartnerTimeAudit> _audits = [];
  bool _loading = true;
  bool _enabled = false;
  bool _showAudit = false;
  String? _staffFilter;
  int _daysBack = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final enabled =
          await PartnerWorkforceService.isEnabled(widget.partner.id);
      if (!enabled) {
        if (mounted) {
          setState(() {
            _enabled = false;
            _loading = false;
            _entries = [];
          });
        }
        return;
      }
      final now = DateTime.now();
      final from = now.subtract(Duration(days: _daysBack));
      final results = await Future.wait([
        PartnerWorkforceService.listEntries(
          partnerId: widget.partner.id,
          from: from,
          to: now.add(const Duration(days: 1)),
          staffId: _staffFilter,
        ),
        PartnerWorkforceService.listStaff(
          partnerId: widget.partner.id,
          includeInactive: true,
        ),
        PartnerWorkforceService.listAudits(partnerId: widget.partner.id),
      ]);
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _entries = results[0] as List<PartnerTimeEntry>;
        _staff = results[1] as List<PartnerStaff>;
        _audits = results[2] as List<PartnerTimeAudit>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  double get _totalHours {
    var m = 0;
    for (final e in _entries) {
      if (e.isOpen) {
        m += DateTime.now().difference(e.clockIn).inMinutes;
      } else {
        m += e.duration?.inMinutes ?? 0;
      }
    }
    return m / 60.0;
  }

  int get _openCount => _entries.where((e) => e.isOpen).length;

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
      mime:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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
                  leading: const Icon(Icons.login_rounded,
                      color: DriftProTheme.primaryGreen),
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
                  leading: Icon(Icons.logout_rounded, color: Colors.red.shade700),
                  title: const Text('Ut'),
                  subtitle: Text(outAt == null ? 'Åpen (på jobb)' : fmt.format(outAt!)),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final v = await pick(ctx, outAt ?? inAt);
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lagre')),
          ],
        ),
      ),
    );
    if (ok != true) return;
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

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);
    final dayFmt = DateFormat('EEE d. MMM', 'nb');
    final timeFmt = DateFormat('HH:mm');

    return PartnerPortalPageShell(
      title: 'Timer',
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
                      Center(
                        child: Text('Timer er ikke aktivert for denne bedriften.'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      Row(
                        children: [
                          if (_enabled)
                            IconButton(
                              tooltip: 'Eksporter Excel',
                              onPressed: _entries.isEmpty ? null : _exportExcel,
                              icon: const Icon(Icons.file_download_outlined),
                            ),
                          IconButton(
                            tooltip: _showAudit ? 'Skjul logg' : 'Endringslogg',
                            onPressed: () =>
                                setState(() => _showAudit = !_showAudit),
                            icon: Icon(
                              Icons.history,
                              color: _showAudit
                                  ? DriftProTheme.primaryGreen
                                  : null,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      Row(
                        children: [
                          _StatPill(
                            label: 'Timer',
                            value: _totalHours.toStringAsFixed(1),
                            accent: DriftProTheme.primaryGreen,
                          ),
                          const SizedBox(width: 8),
                          _StatPill(
                            label: 'Poster',
                            value: '${_entries.length}',
                            accent: Colors.blueGrey,
                          ),
                          const SizedBox(width: 8),
                          _StatPill(
                            label: 'På jobb',
                            value: '$_openCount',
                            accent: _openCount > 0
                                ? Colors.orange.shade800
                                : Colors.blueGrey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final d in const [7, 14, 30, 90])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('$d d'),
                                  selected: _daysBack == d,
                                  onSelected: (_) {
                                    setState(() => _daysBack = d);
                                    _load();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        // ignore: deprecated_member_use
                        value: _staffFilter,
                        decoration: const InputDecoration(
                          labelText: 'Filtrer ansatt',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Alle ansatte'),
                          ),
                          ..._staff.map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.fullName),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _staffFilter = v);
                          _load();
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Trykk en rad for å redigere inn/ut',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 8),
                      if (_entries.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Ingen timer i perioden',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        )
                      else
                        ..._entries.map((e) {
                          final hours = e.isOpen
                              ? PartnerWorkforceService.formatDurationClock(
                                  DateTime.now().difference(e.clockIn),
                                )
                              : PartnerWorkforceService.formatHours(e.duration);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _editEntry(e),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: e.isOpen
                                          ? DriftProTheme.primaryGreen
                                              .withValues(alpha: 0.35)
                                          : Colors.black.withValues(alpha: 0.06),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: (e.isOpen
                                                  ? DriftProTheme.primaryGreen
                                                  : Colors.blueGrey)
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          e.isOpen
                                              ? Icons.timelapse_rounded
                                              : Icons.schedule_rounded,
                                          color: e.isOpen
                                              ? DriftProTheme.primaryGreen
                                              : Colors.blueGrey,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.staffName ?? 'Ansatt',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${dayFmt.format(e.clockIn.toLocal())} · '
                                              '${timeFmt.format(e.clockIn.toLocal())}'
                                              ' → '
                                              '${e.isOpen ? 'pågår' : timeFmt.format(e.clockOut!.toLocal())}',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: muted,
                                              ),
                                            ),
                                            if (e.note != null &&
                                                e.note!.trim().isNotEmpty)
                                              Text(
                                                e.note!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: muted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            hours,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: e.isOpen
                                                  ? DriftProTheme.primaryGreen
                                                  : null,
                                            ),
                                          ),
                                          Icon(Icons.edit_outlined,
                                              size: 16, color: muted),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      if (_showAudit) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Endringslogg',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._audits.take(50).map((a) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                '${a.action} · ${a.changedByName ?? 'system'}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                DateFormat('dd.MM.yyyy HH:mm')
                                    .format(a.changedAt.toLocal()),
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
