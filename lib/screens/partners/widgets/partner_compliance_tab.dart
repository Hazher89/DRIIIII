import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Møter, audit, SMS-varsler, arkiv og sporing — samlet oppfølging.
class PartnerComplianceTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;

  const PartnerComplianceTab({
    super.key,
    required this.partner,
    required this.onChanged,
  });

  @override
  State<PartnerComplianceTab> createState() => _PartnerComplianceTabState();
}

class _PartnerComplianceTabState extends State<PartnerComplianceTab> {
  List<PartnerMeeting> _meetings = [];
  bool _loading = true;
  bool _showArchive = false;

  Partner get _p => widget.partner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final m = await PartnerService.fetchMeetings(_p.id);
    if (mounted) {
      setState(() {
        _meetings = m;
        _loading = false;
      });
    }
  }

  List<PartnerMeeting> get _active =>
      _meetings.where((m) => !m.isArchived && m.status != 'avlyst').toList();

  List<PartnerMeeting> get _archived =>
      _meetings.where((m) => m.isArchived || m.status == 'gjennomfort').toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  Future<void> _pickAuditDates() async {
    final last = await showDatePicker(
      context: context,
      initialDate: _p.lastAuditAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (last == null) return;
    final next = await showDatePicker(
      context: context,
      initialDate: _p.nextAuditAt ?? DateTime.now().add(const Duration(days: 180)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (next == null) return;

    await PartnerService.updatePartner(
      _p.id,
      Partner(
        id: _p.id,
        companyId: _p.companyId,
        orgNumber: _p.orgNumber,
        name: _p.name,
        tradeName: _p.tradeName,
        ownerName: _p.ownerName,
        phone: _p.phone,
        email: _p.email,
        address: _p.address,
        postalCode: _p.postalCode,
        city: _p.city,
        country: _p.country,
        notes: _p.notes,
        vehicleCountRegistered: _p.vehicleCountRegistered,
        vehicleMaxPayloadKg: _p.vehicleMaxPayloadKg,
        euApproved: _p.euApproved,
        hasTransportLicense: _p.hasTransportLicense,
        transportLicenseCount: _p.transportLicenseCount,
        employeeCount: _p.employeeCount,
        auditStatus: _p.auditStatus,
        auditPlate: _p.auditPlate,
        brregSnapshot: _p.brregSnapshot,
        lastMeetingAt: _p.lastMeetingAt,
        nextMeetingAt: _p.nextMeetingAt,
        lastAuditAt: last,
        nextAuditAt: next,
        isActive: _p.isActive,
        routesOwnerOnly: _p.routesOwnerOnly,
        createdAt: _p.createdAt,
      ),
    );
    await widget.onChanged();
  }

  Future<void> _updateAuditStatus(String status) async {
    await PartnerService.updatePartner(
      _p.id,
      Partner(
        id: _p.id,
        companyId: _p.companyId,
        orgNumber: _p.orgNumber,
        name: _p.name,
        tradeName: _p.tradeName,
        ownerName: _p.ownerName,
        phone: _p.phone,
        email: _p.email,
        address: _p.address,
        postalCode: _p.postalCode,
        city: _p.city,
        country: _p.country,
        notes: _p.notes,
        vehicleCountRegistered: _p.vehicleCountRegistered,
        vehicleMaxPayloadKg: _p.vehicleMaxPayloadKg,
        euApproved: _p.euApproved,
        hasTransportLicense: _p.hasTransportLicense,
        transportLicenseCount: _p.transportLicenseCount,
        employeeCount: _p.employeeCount,
        auditStatus: status,
        auditPlate: _p.auditPlate,
        brregSnapshot: _p.brregSnapshot,
        lastMeetingAt: _p.lastMeetingAt,
        nextMeetingAt: _p.nextMeetingAt,
        lastAuditAt: _p.lastAuditAt,
        nextAuditAt: _p.nextAuditAt,
        isActive: _p.isActive,
        routesOwnerOnly: _p.routesOwnerOnly,
        createdAt: _p.createdAt,
      ),
    );
    await widget.onChanged();
  }

  Future<void> _createMeeting() async {
    final titleCtrl = TextEditingController(text: 'Dirigert møte');
    final locCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var meetingType = 'dirigert';
    var sendSms = true;
    DateTime when = DateTime.now().add(const Duration(days: 7));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Planlegg oppfølging'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: meetingType,
                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'dirigert', child: Text('Dirigert møte')),
                    DropdownMenuItem(value: 'audit', child: Text('Audit / revisjon')),
                    DropdownMenuItem(value: 'telefon', child: Text('Telefonmøte')),
                    DropdownMenuItem(value: 'oppfolging', child: Text('Oppfølging')),
                  ],
                  onChanged: (v) => setSt(() {
                    meetingType = v ?? 'dirigert';
                    if (meetingType == 'audit') titleCtrl.text = 'Audit / revisjon';
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Tittel', border: OutlineInputBorder()),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat('dd.MM.yyyy HH:mm').format(when)),
                  subtitle: const Text('Dato og tid'),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: when,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (d == null) return;
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                    if (t == null) return;
                    setSt(() {
                      when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                    });
                  },
                ),
                TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(labelText: 'Sted / lenke', border: OutlineInputBorder()),
                ),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notater', border: OutlineInputBorder()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Send SMS-varsel nå'),
                  subtitle: Text('Til ${_p.phone ?? "telefon i bedriftsprofil"}'),
                  value: sendSms,
                  onChanged: (v) => setSt(() => sendSms = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Opprett')),
          ],
        ),
      ),
    );

    if (ok != true) {
      titleCtrl.dispose();
      locCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    try {
      final created = await PartnerService.addMeeting(
        PartnerMeeting(
          id: '',
          partnerId: _p.id,
          companyId: _p.companyId,
          title: titleCtrl.text.trim(),
          scheduledAt: when,
          location: locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          meetingType: meetingType,
          status: 'planlagt',
          createdAt: DateTime.now(),
        ),
        companyId: _p.companyId,
      );

      await PartnerService.updatePartner(
        _p.id,
        Partner(
          id: _p.id,
          companyId: _p.companyId,
          orgNumber: _p.orgNumber,
          name: _p.name,
          tradeName: _p.tradeName,
          ownerName: _p.ownerName,
          phone: _p.phone,
          email: _p.email,
          address: _p.address,
          postalCode: _p.postalCode,
          city: _p.city,
          country: _p.country,
          notes: _p.notes,
          vehicleCountRegistered: _p.vehicleCountRegistered,
          vehicleMaxPayloadKg: _p.vehicleMaxPayloadKg,
          euApproved: _p.euApproved,
          hasTransportLicense: _p.hasTransportLicense,
          transportLicenseCount: _p.transportLicenseCount,
          employeeCount: _p.employeeCount,
          auditStatus: meetingType == 'audit' ? 'planlagt' : _p.auditStatus,
          auditPlate: _p.auditPlate,
          brregSnapshot: _p.brregSnapshot,
          lastMeetingAt: _p.lastMeetingAt,
          nextMeetingAt: when,
          lastAuditAt: _p.lastAuditAt,
          nextAuditAt: meetingType == 'audit' ? when : _p.nextAuditAt,
          isActive: _p.isActive,
          routesOwnerOnly: _p.routesOwnerOnly,
          createdAt: _p.createdAt,
        ),
      );

      if (sendSms && _p.phone != null && _p.phone!.trim().length >= 8) {
        final msg =
            'Hei ${_p.name}. ${PartnerMeeting.meetingTypeLabel(meetingType)} '
            '${when.day}.${when.month}.${when.year} kl ${when.hour.toString().padLeft(2, "0")}:${when.minute.toString().padLeft(2, "0")}. Mvh MAVI';
        final n = await PartnerService.sendMeetingSms(
          partnerId: _p.id,
          message: msg,
          meetingId: created.id,
        );
        if (mounted && n == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Møte opprettet — SMS kunne ikke sendes')),
          );
        }
      }

      await _load();
      await widget.onChanged();
    } finally {
      titleCtrl.dispose();
      locCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  Future<void> _sendSms(PartnerMeeting m) async {
    if (_p.phone == null || _p.phone!.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Legg inn telefonnummer på bedriften først')),
      );
      return;
    }
    final when = m.scheduledAt.toLocal();
    final msg =
        'Hei ${_p.name}. Påminnelse: ${m.title} '
        '${when.day}.${when.month}.${when.year} kl ${when.hour.toString().padLeft(2, "0")}:${when.minute.toString().padLeft(2, "0")}. Mvh MAVI';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SMS-varsel?'),
        content: Text('Til ${_p.phone}:\n\n$msg'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await PartnerService.sendMeetingSms(
      partnerId: _p.id,
      message: msg,
      meetingId: m.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n > 0 ? 'SMS sendt' : 'SMS feilet — sjekk oppsett')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }

    final planned = _active.where((m) => m.status == 'planlagt').length;
    final audits = _meetings.where((m) => m.isAudit).length;

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await widget.onChanged();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          PartnerHeroBanner(
            compact: true,
            title: 'Oppfølging & revisjon',
            subtitle: 'Møter, audit, SMS-varsler og arkiv med full sporing.',
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.track_changes_outlined, color: Colors.white),
            ),
          ),
          PartnerKpiStrip(
            items: [
              PartnerKpiItem(
                label: 'Planlagt',
                value: '$planned',
                color: DriftProTheme.info,
                icon: Icons.event_outlined,
              ),
              PartnerKpiItem(
                label: 'Audit',
                value: '${_p.auditStatusLabel}',
                color: DriftProTheme.warning,
                icon: Icons.fact_check_outlined,
              ),
              PartnerKpiItem(
                label: 'Audit-møter',
                value: '$audits',
                color: DriftProTheme.accentBlue,
                icon: Icons.assignment_turned_in_outlined,
              ),
            ],
          ),
          PartnerSectionCard(
            icon: Icons.fact_check_outlined,
            title: 'Revisjon / audit-status',
            subtitle: 'Siste og neste audit-dato for bedriften.',
            children: [
              DropdownButtonFormField<String>(
                initialValue: _p.auditStatus,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'ukjent', child: Text('Ukjent')),
                  DropdownMenuItem(value: 'planlagt', child: Text('Planlagt')),
                  DropdownMenuItem(value: 'ok', child: Text('OK')),
                  DropdownMenuItem(value: 'avvik', child: Text('Avvik')),
                  DropdownMenuItem(value: 'utlopt', child: Text('Utløpt')),
                ],
                onChanged: (v) {
                  if (v != null) _updateAuditStatus(v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Audit-datoer'),
                subtitle: Text(
                  'Siste: ${_p.lastAuditAt != null ? DateFormat('dd.MM.yyyy').format(_p.lastAuditAt!) : "—"}\n'
                  'Neste: ${_p.nextAuditAt != null ? DateFormat('dd.MM.yyyy').format(_p.nextAuditAt!) : "—"}',
                ),
                trailing: IconButton(icon: const Icon(Icons.edit_calendar), onPressed: _pickAuditDates),
              ),
            ],
          ),
          PartnerSectionCard(
            icon: Icons.event_note_outlined,
            title: 'Planlagte møter & audit',
            trailing: FilledButton.icon(
              onPressed: _createMeeting,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ny'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
            ),
            children: [
              if (_active.isEmpty)
                PartnerEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Ingen planlagte møter',
                  subtitle: 'Opprett dirigert møte eller audit med valgfri SMS.',
                )
              else
                ..._active.map((m) => _meetingCard(m, archived: false)),
            ],
          ),
          Row(
            children: [
              Text('Arkiv & historikk', style: DriftProTheme.headingSm),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showArchive = !_showArchive),
                child: Text(_showArchive ? 'Skjul' : 'Vis (${_archived.length})'),
              ),
            ],
          ),
          if (_showArchive)
            ..._archived.map((m) => _meetingCard(m, archived: true)),
        ],
      ),
    );
  }

  Widget _meetingCard(PartnerMeeting m, {required bool archived}) {
    final when = m.scheduledAt.toLocal();
    Color statusColor = DriftProTheme.info;
    if (m.status == 'gjennomfort') statusColor = DriftProTheme.success;
    if (m.status == 'avlyst') statusColor = DriftProTheme.error;
    if (m.isAudit) statusColor = DriftProTheme.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: statusColor.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                PartnerStatusBadge(
                  label: PartnerMeeting.statusLabel(m.status),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${PartnerMeeting.meetingTypeLabel(m.meetingType)} · '
              '${DateFormat('dd.MM.yyyy HH:mm').format(when)}'
              '${m.location != null ? " · ${m.location}" : ""}',
              style: DriftProTheme.bodySm,
            ),
            if (m.notes != null && m.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(m.notes!, style: DriftProTheme.caption),
              ),
            if (m.smsSentAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.sms_outlined, size: 14, color: DriftProTheme.success),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'SMS ${DateFormat('dd.MM HH:mm').format(m.smsSentAt!.toLocal())}',
                        style: DriftProTheme.caption,
                      ),
                    ),
                  ],
                ),
              ),
            if (m.completedAt != null)
              Text(
                'Gjennomført ${DateFormat('dd.MM.yyyy').format(m.completedAt!.toLocal())}',
                style: DriftProTheme.caption,
              ),
            if (!archived && m.status == 'planlagt') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _sendSms(m),
                    icon: const Icon(Icons.sms_outlined, size: 16),
                    label: const Text('SMS'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await PartnerService.completeMeeting(m.id);
                      await _load();
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Gjennomført'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await PartnerService.archiveMeeting(m.id);
                      await _load();
                    },
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Arkiver'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
