import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';

class PartnerDetailScreen extends StatefulWidget {
  final Partner partner;
  const PartnerDetailScreen({super.key, required this.partner});

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Partner _p;

  @override
  void initState() {
    super.initState();
    _p = widget.partner;
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final fresh = await PartnerService.fetchPartner(_p.id);
    if (fresh != null && mounted) setState(() => _p = fresh);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_p.name),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Dokumenter'),
            Tab(text: 'Møte & revisjon'),
            Tab(text: 'Rute-PDF'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(partner: _p, onSaved: _reload),
          _DocumentsTab(partner: _p, onChanged: _reload),
          _MeetingAuditTab(partner: _p, onChanged: _reload),
          _RoutesTab(partner: _p, onChanged: _reload),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onSaved;
  const _OverviewTab({required this.partner, required this.onSaved});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  late final TextEditingController _owner;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _postal;
  late final TextEditingController _city;
  late final TextEditingController _veh;
  late final TextEditingController _payload;
  late final TextEditingController _notes;
  bool? _eu;

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
    _payload = TextEditingController(text: p.vehicleMaxPayloadKg?.toString() ?? '');
    _notes = TextEditingController(text: p.notes ?? '');
    _eu = p.euApproved;
  }

  @override
  void didUpdateWidget(covariant _OverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partner.id != widget.partner.id) return;
    final p = widget.partner;
    _owner.text = p.ownerName ?? '';
    _phone.text = p.phone ?? '';
    _email.text = p.email ?? '';
    _address.text = p.address ?? '';
    _postal.text = p.postalCode ?? '';
    _city.text = p.city ?? '';
    _veh.text = '${p.vehicleCountRegistered}';
    _payload.text = p.vehicleMaxPayloadKg?.toString() ?? '';
    _notes.text = p.notes ?? '';
    _eu = p.euApproved;
  }

  @override
  void dispose() {
    _owner.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _postal.dispose();
    _city.dispose();
    _veh.dispose();
    _payload.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final path = Partner(
      id: widget.partner.id,
      companyId: widget.partner.companyId,
      orgNumber: widget.partner.orgNumber,
      name: widget.partner.name,
      tradeName: widget.partner.tradeName,
      ownerName: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      postalCode: _postal.text.trim().isEmpty ? null : _postal.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      country: widget.partner.country,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      vehicleCountRegistered: int.tryParse(_veh.text) ?? 0,
      vehicleMaxPayloadKg: int.tryParse(_payload.text),
      euApproved: _eu,
      brregSnapshot: widget.partner.brregSnapshot,
      lastMeetingAt: widget.partner.lastMeetingAt,
      nextMeetingAt: widget.partner.nextMeetingAt,
      lastAuditAt: widget.partner.lastAuditAt,
      nextAuditAt: widget.partner.nextAuditAt,
      createdAt: widget.partner.createdAt,
    );
    await PartnerService.updatePartner(widget.partner.id, path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lagret')));
      await widget.onSaved();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.partner;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Org.nr ${p.orgNumber ?? "—"}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        TextField(
          controller: _owner,
          decoration: const InputDecoration(labelText: 'Eier / kontakt', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'E-post', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _address,
          decoration: const InputDecoration(labelText: 'Adresse', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _postal,
                decoration: const InputDecoration(labelText: 'Postnr', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'Sted', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _veh,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ant. kjøretøy', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _payload,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nyttelast kg', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        SwitchListTile(
          title: const Text('EU-godkjent (oppgitt)'),
          value: _eu ?? false,
          onChanged: (v) => setState(() => _eu = v),
        ),
        TextField(
          controller: _notes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notater', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
          child: const Text('Lagre endringer'),
        ),
      ],
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
    final d = await PartnerService.fetchDocuments(widget.partner.id);
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

  @override
  Widget build(BuildContext context) {
    final p = widget.partner;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: const Text('Revisjon / audit (datoer)'),
            subtitle: Text(
              'Siste: ${p.lastAuditAt != null ? _d(p.lastAuditAt!) : "—"} | Neste: ${p.nextAuditAt != null ? _d(p.nextAuditAt!) : "—"}',
            ),
            trailing: const Icon(Icons.edit),
            onTap: _pickAuditDates,
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
                    return Card(
                      child: ListTile(
                        title: Text(r.title ?? 'Rute'),
                        subtitle: Text('${r.shareDate.toString().split(" ").first} · ${r.pdfStoragePath}'),
                        trailing: r.isDailyShare ? const Chip(label: Text('Daglig')) : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
