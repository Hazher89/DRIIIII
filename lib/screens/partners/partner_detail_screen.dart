import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_assigned_routes_tab.dart';
import 'widgets/partner_fri_tab.dart';
import 'widgets/partner_overview_tab.dart';

class PartnerDetailScreen extends StatefulWidget {
  final Partner partner;
  const PartnerDetailScreen({super.key, required this.partner});

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Partner _p;
  List<PartnerVehicle> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    _p = widget.partner;
    _tabs = TabController(length: 7, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final fresh = await PartnerService.fetchPartner(_p.id);
    final vehicles = await PartnerService.fetchVehicles(_p.id);
    if (fresh != null && mounted) {
      setState(() {
        _p = fresh;
        _vehicles = vehicles;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett samarbeidspartner?'),
        content: Text(
          '«${_p.name}» og alle tilknyttede data (biler, ruter, dokumenter) '
          'fjernes permanent fra systemet.',
        ),
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
    if (ok != true || !mounted) return;
    await PartnerService.deletePartner(_p.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partner slettet')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_p.name),
        actions: [
          IconButton(
            tooltip: 'Slett partner',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _confirmDelete,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Tildelte ruter'),
            Tab(text: 'Dokumenter'),
            Tab(text: 'Møte & revisjon'),
            Tab(text: 'Rute-PDF'),
            Tab(text: 'Oppsummering'),
            Tab(text: 'Fri'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          PartnerOverviewTab(partner: _p, vehicles: _vehicles, onSaved: _reload),
          PartnerAssignedRoutesTab(partner: _p),
          _DocumentsTab(partner: _p, onChanged: _reload),
          _MeetingAuditTab(partner: _p, onChanged: _reload),
          _RoutesTab(partner: _p, onChanged: _reload),
          _SummaryTab(partner: _p, onChanged: _reload),
          PartnerFriTab(partner: _p, vehicles: _vehicles),
        ],
      ),
    );
  }
}


class _DocumentsTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;
  const _DocumentsTab({required this.partner, required this.onChanged});

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  List<PartnerDocument> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await PartnerService.fetchDocuments(
      widget.partner.id,
      docCategories: const ['general', 'agreement'],
    );
    if (mounted) setState(() => _list = d);
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final path = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Del dokument'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Tittel')),
            TextField(
              controller: path,
              decoration: const InputDecoration(
                labelText: 'Storage-sti eller URL',
                hintText: 'bucket/path eller https://...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Legg til')),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      await PartnerService.addDocument(
        PartnerDocument(
          id: '',
          partnerId: widget.partner.id,
          companyId: widget.partner.companyId,
          title: title.text.trim(),
          storagePath: path.text.trim().isEmpty ? null : path.text.trim(),
          docCategory: 'general',
          createdAt: DateTime.now(),
        ),
      );
      await _load();
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Legg til dokument'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? const Center(child: Text('Ingen dokumenter.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final d = _list[i];
                    return Card(
                      child: ListTile(
                        title: Text(d.title),
                        subtitle: Text(d.storagePath ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await PartnerService.deleteDocument(d.id);
                            await _load();
                            await widget.onChanged();
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MeetingAuditTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;
  const _MeetingAuditTab({required this.partner, required this.onChanged});

  @override
  State<_MeetingAuditTab> createState() => _MeetingAuditTabState();
}

class _MeetingAuditTabState extends State<_MeetingAuditTab> {
  List<PartnerMeeting> _meetings = [];

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    final m = await PartnerService.fetchMeetings(widget.partner.id);
    if (mounted) setState(() => _meetings = m);
  }

  Future<void> _pickAuditDates() async {
    final p = widget.partner;
    final last = await showDatePicker(
      context: context,
      initialDate: p.lastAuditAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (last == null) return;
    final next = await showDatePicker(
      context: context,
      initialDate: p.nextAuditAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (next == null) return;
    final upd = Partner(
      id: p.id,
      companyId: p.companyId,
      orgNumber: p.orgNumber,
      name: p.name,
      tradeName: p.tradeName,
      ownerName: p.ownerName,
      phone: p.phone,
      email: p.email,
      address: p.address,
      postalCode: p.postalCode,
      city: p.city,
      country: p.country,
      notes: p.notes,
      vehicleCountRegistered: p.vehicleCountRegistered,
      vehicleMaxPayloadKg: p.vehicleMaxPayloadKg,
      euApproved: p.euApproved,
      hasTransportLicense: p.hasTransportLicense,
      transportLicenseCount: p.transportLicenseCount,
      employeeCount: p.employeeCount,
      auditStatus: p.auditStatus,
      auditPlate: p.auditPlate,
      brregSnapshot: p.brregSnapshot,
      lastMeetingAt: p.lastMeetingAt,
      nextMeetingAt: p.nextMeetingAt,
      lastAuditAt: last,
      nextAuditAt: next,
      createdAt: p.createdAt,
    );
    await PartnerService.updatePartner(p.id, upd);
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _addMeeting() async {
    final title = TextEditingController(text: 'Dirigert møte');
    DateTime when = DateTime.now().add(const Duration(days: 7));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Planlegg møte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Tittel')),
              ListTile(
                title: Text('${when.day}.${when.month}.${when.year} ${when.hour}:${when.minute.toString().padLeft(2, "0")}'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: when,
                    firstDate: DateTime(2000),
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await PartnerService.addMeeting(
        PartnerMeeting(
          id: '',
          partnerId: widget.partner.id,
          title: title.text.trim(),
          scheduledAt: when,
          isDirect: true,
          createdAt: DateTime.now(),
        ),
      );
      await PartnerService.updatePartner(
        widget.partner.id,
        Partner(
          id: widget.partner.id,
          companyId: widget.partner.companyId,
          orgNumber: widget.partner.orgNumber,
          name: widget.partner.name,
          tradeName: widget.partner.tradeName,
          ownerName: widget.partner.ownerName,
          phone: widget.partner.phone,
          email: widget.partner.email,
          address: widget.partner.address,
          postalCode: widget.partner.postalCode,
          city: widget.partner.city,
          country: widget.partner.country,
          notes: widget.partner.notes,
          vehicleCountRegistered: widget.partner.vehicleCountRegistered,
          vehicleMaxPayloadKg: widget.partner.vehicleMaxPayloadKg,
          euApproved: widget.partner.euApproved,
          hasTransportLicense: widget.partner.hasTransportLicense,
          transportLicenseCount: widget.partner.transportLicenseCount,
          employeeCount: widget.partner.employeeCount,
          auditStatus: widget.partner.auditStatus,
          auditPlate: widget.partner.auditPlate,
          brregSnapshot: widget.partner.brregSnapshot,
          lastMeetingAt: widget.partner.lastMeetingAt,
          nextMeetingAt: when,
          lastAuditAt: widget.partner.lastAuditAt,
          nextAuditAt: widget.partner.nextAuditAt,
          createdAt: widget.partner.createdAt,
        ),
      );
      await _loadMeetings();
      await widget.onChanged();
    }
  }

  Future<void> _notifyMeetingSms() async {
    final p = widget.partner;
    if (p.phone == null || p.phone!.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Legg inn telefonnummer på partneren først')),
      );
      return;
    }
    final when = p.nextMeetingAt;
    final msg = when != null
        ? 'Hei ${p.name}. Påminnelse: møte ${when.day}.${when.month}.${when.year} kl ${when.hour}:${when.minute.toString().padLeft(2, "0")}. Mvh MAVI'
        : 'Hei ${p.name}. Påminnelse om planlagt møte med MAVI. Ta kontakt for tidspunkt. Mvh MAVI';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SMS-varsel om møte?'),
        content: Text('Til ${p.phone}:\n\n$msg'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send SMS')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await PartnerService.notifyMeetingSms(partnerId: p.id, message: msg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n > 0 ? 'SMS lagt i kø' : 'Kunne ikke sende SMS — sjekk telefon og SMS-oppsett'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.partner;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Revisjon / audit'),
            subtitle: Text(
              'Status: ${p.auditStatusLabel}'
              '${p.auditPlate != null ? " · ${p.auditPlate}" : ""}\n'
              'Siste: ${p.lastAuditAt != null ? _d(p.lastAuditAt!) : "—"} | Neste: ${p.nextAuditAt != null ? _d(p.nextAuditAt!) : "—"}',
            ),
            trailing: const Icon(Icons.edit),
            onTap: _pickAuditDates,
          ),
        ),
        if (p.nextMeetingAt != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.sms_outlined, color: DriftProTheme.primaryGreen),
              title: const Text('Varsle om neste møte (SMS)'),
              subtitle: Text(
                'Neste møte: ${p.nextMeetingAt!.day}.${p.nextMeetingAt!.month}.${p.nextMeetingAt!.year}',
              ),
              trailing: FilledButton(
                onPressed: _notifyMeetingSms,
                child: const Text('Send'),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Møter', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(onPressed: _addMeeting, icon: const Icon(Icons.add), label: const Text('Nytt møte')),
          ],
        ),
        ..._meetings.map(
          (m) => Card(
            child: ListTile(
              title: Text(m.title),
              subtitle: Text('${m.scheduledAt.toLocal()} ${m.isDirect ? "· direkte" : ""}'),
            ),
          ),
        ),
      ],
    );
  }

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

/// Oppsummerings-PDF: egen kategori (doc_category=summary). RLS: kun MAVI i selskapet + denne partneren.
class _SummaryTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;
  const _SummaryTab({required this.partner, required this.onChanged});

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  List<PartnerDocument> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await PartnerService.fetchDocuments(
      widget.partner.id,
      docCategories: const ['summary'],
    );
    if (mounted) setState(() => _list = d);
  }

  Future<void> _uploadPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke lese PDF-fil.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final title = TextEditingController(text: 'Oppsummering');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last opp oppsummering (PDF)'),
        content: TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: 'Tittel',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Last opp')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'company_${widget.partner.companyId}/partner_summaries/${widget.partner.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    try {
      await PartnerService.uploadPartnerDocumentPdf(storagePath: storagePath, bytes: bytes);
      await PartnerService.addDocument(
        PartnerDocument(
          id: '',
          partnerId: widget.partner.id,
          companyId: widget.partner.companyId,
          title: title.text.trim().isEmpty ? 'Oppsummering' : title.text.trim(),
          storagePath: storagePath,
          fileName: file.name,
          mimeType: 'application/pdf',
          docCategory: 'summary',
          createdAt: DateTime.now(),
        ),
      );
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oppsummering er delt med partner (kun deres tilgang).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opplasting feilet: $e')));
      }
    } finally {
      title.dispose();
    }
  }

  Future<void> _open(PartnerDocument d) async {
    final p = d.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.getDocumentPdfSignedUrl(p);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Oppsummerings-PDF er kun synlig for dere internt og for denne samarbeidspartneren (dataminimering).',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _uploadPdf,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Last opp oppsummering-PDF'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? const Center(child: Text('Ingen oppsummering delt ennå.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final d = _list[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(d.title),
                        subtitle: Text(d.fileName ?? d.storagePath ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _open(d),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RoutesTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;
  const _RoutesTab({required this.partner, required this.onChanged});

  @override
  State<_RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends State<_RoutesTab> {
  List<PartnerRouteShare> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await PartnerService.fetchRouteShares(widget.partner.id);
    if (mounted) setState(() => _list = r);
  }

  Future<void> _add() async {
    final title = TextEditingController(text: 'Dagens rute');
    final path = TextEditingController();
    var daily = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Del rute-PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Tittel')),
              TextField(
                controller: path,
                decoration: const InputDecoration(labelText: 'PDF (storage-sti eller URL)', border: OutlineInputBorder()),
              ),
              CheckboxListTile(
                value: daily,
                onChanged: (v) => setSt(() => daily = v ?? false),
                title: const Text('Daglig rutine / plan'),
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
    if (ok == true && path.text.trim().isNotEmpty) {
      await PartnerService.addRouteShare(
        PartnerRouteShare(
          id: '',
          partnerId: widget.partner.id,
          companyId: widget.partner.companyId,
          title: title.text.trim(),
          pdfStoragePath: path.text.trim(),
          shareDate: DateTime.now(),
          isDailyShare: daily,
          createdAt: DateTime.now(),
        ),
      );
      await _load();
      await widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Legg til rute-PDF'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? const Center(child: Text('Ingen rutedeling.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final r = _list[i];
                    final ackColor = switch (r.ackStatus) {
                      'accepted' => Colors.green,
                      'rejected' => Colors.red,
                      _ => Colors.orange,
                    };
                    final ackLabel = switch (r.ackStatus) {
                      'accepted' => 'Akseptert',
                      'rejected' => 'Ikke akseptert',
                      _ => 'Venter svar',
                    };
                    return Card(
                      child: ListTile(
                        title: Text(r.title ?? 'Rute'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r.shareDate.toString().split(" ").first} · ${r.pdfStoragePath}'),
                            const SizedBox(height: 4),
                            Text(
                              ackLabel,
                              style: TextStyle(
                                color: ackColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (r.ackComment != null && r.ackComment!.trim().isNotEmpty)
                              Text(
                                'Kommentar: ${r.ackComment}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                        trailing: r.isDailyShare
                            ? const Chip(label: Text('Daglig'))
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
