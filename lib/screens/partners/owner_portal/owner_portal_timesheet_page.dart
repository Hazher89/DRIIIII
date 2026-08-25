import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/partner_workforce_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/bytes_download.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_workforce.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';

class OwnerPortalTimesheetPage extends StatefulWidget {
  final Partner partner;
  final bool isSuperAdmin;

  const OwnerPortalTimesheetPage({
    super.key,
    required this.partner,
    this.isSuperAdmin = false,
  });

  @override
  State<OwnerPortalTimesheetPage> createState() => _OwnerPortalTimesheetPageState();
}

class _OwnerPortalTimesheetPageState extends State<OwnerPortalTimesheetPage> {
  List<PartnerTimeEntry> _entries = [];
  List<PartnerTimeAudit> _audits = [];
  bool _loading = true;
  bool _enabled = false;
  bool _showAudit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final enabled = await PartnerWorkforceService.isEnabled(widget.partner.id);
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
      final from = DateTime(now.year, now.month, 1);
      final entries = await PartnerWorkforceService.listEntries(
        partnerId: widget.partner.id,
        from: from,
        to: now.add(const Duration(days: 1)),
      );
      final audits = await PartnerWorkforceService.listAudits(
        partnerId: widget.partner.id,
      );
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _entries = entries;
        _audits = audits;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _exportExcel() async {
    final bytes = PartnerWorkforceService.buildExcelBytes(
      partnerName: widget.partner.name,
      entries: _entries,
    );
    final name =
        'timer_${widget.partner.name.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}_${DateFormat('yyyyMM').format(DateTime.now())}.xlsx';
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Rediger — ${e.staffName ?? 'ansatt'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Inn'),
                subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(inAt)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: inAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d == null) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(inAt),
                  );
                  if (t == null) return;
                  setLocal(() {
                    inAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  });
                },
              ),
              ListTile(
                title: const Text('Ut'),
                subtitle: Text(
                  outAt == null
                      ? 'Åpen'
                      : DateFormat('dd.MM.yyyy HH:mm').format(outAt!),
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: outAt ?? inAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d == null) return;
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(outAt ?? inAt),
                  );
                  if (t == null) return;
                  setLocal(() {
                    outAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  });
                },
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Merknad'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
          ],
        ),
      ),
    );
    if (ok != true) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM HH:mm');
    return PartnerPortalPageShell(
      title: 'Timer',
      actions: [
        if (_enabled)
          IconButton(
            tooltip: 'Eksporter Excel',
            onPressed: _entries.isEmpty ? null : _exportExcel,
            icon: const Icon(Icons.file_download_outlined),
          ),
        IconButton(
          tooltip: _showAudit ? 'Skjul logg' : 'Endringslogg',
          onPressed: () => setState(() => _showAudit = !_showAudit),
          icon: const Icon(Icons.history),
        ),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
          tooltip: 'Logg ut',
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
      body: _loading
          ? const DriftProLoadingCenter()
          : !_enabled
              ? const Center(
                  child: Text('Timer er ikke aktivert for denne bedriften.'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      Text(
                        'Denne måneden · trykk for å redigere · Excel via nedlastingsikon',
                        style: DriftProTheme.caption,
                      ),
                      const SizedBox(height: 8),
                      ..._entries.map(
                        (e) => Card(
                          child: ListTile(
                            title: Text(e.staffName ?? 'Ansatt'),
                            subtitle: Text(
                              '${fmt.format(e.clockIn.toLocal())}'
                              '${e.clockOut != null ? ' → ${fmt.format(e.clockOut!.toLocal())}' : ' → (åpen)'}'
                              '${e.duration != null ? ' · ${(e.duration!.inMinutes / 60).toStringAsFixed(1)} t' : ''}',
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _editEntry(e),
                          ),
                        ),
                      ),
                      if (_showAudit) ...[
                        const SizedBox(height: 16),
                        Text('Endringslogg', style: DriftProTheme.headingSm),
                        const SizedBox(height: 8),
                        ..._audits.take(40).map(
                          (a) => ListTile(
                            dense: true,
                            title: Text('${a.action} · ${a.changedByName ?? 'system'}'),
                            subtitle: Text(
                              DateFormat('dd.MM.yyyy HH:mm').format(a.changedAt.toLocal()),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
