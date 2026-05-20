import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/route_pdf_text_service.dart';
import '../../core/services/sms/sms_phone_utils.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import 'widgets/partner_sms_message_section.dart';
import 'widgets/partner_sms_route_customers_tab.dart';
import 'widgets/partner_ui.dart';

class PartnerSmsContact {
  final String id;
  final String partnerId;
  final String partnerName;
  final String label;
  final String phone;
  final String kind;

  const PartnerSmsContact({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.label,
    required this.phone,
    required this.kind,
  });
}

/// Parser telefonnummer fra fritekst (linjer, komma, mellomrom).
List<String> parseManualPhoneNumbers(String raw) {
  final out = <String>[];
  final seen = <String>{};

  String? normalize(String input) {
    final n = normalizePhoneNo(input);
    if (n == null) return null;
    return displayPhoneNo(n);
  }

  void add(String? n) {
    if (n == null || seen.contains(n)) return;
    seen.add(n);
    out.add(n);
  }

  for (final line in raw.split(RegExp(r'[\n\r]+'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final byComma = trimmed.split(RegExp(r'[,;|]+'));
    for (final part in byComma) {
      final p = part.trim();
      if (p.isEmpty) continue;
      if (RegExp(r'\s').hasMatch(p) && !p.startsWith('+') && !p.startsWith('00')) {
        for (final token in p.split(RegExp(r'\s+'))) {
          add(normalize(token));
        }
      } else {
        add(normalize(p));
      }
    }
  }
  return out;
}

/// SMS til samarbeidspartnere — enkelt eller masseutsendelse.
class PartnerSmsComposeScreen extends StatefulWidget {
  final bool embedded;

  const PartnerSmsComposeScreen({super.key, this.embedded = false});

  @override
  State<PartnerSmsComposeScreen> createState() => _PartnerSmsComposeScreenState();
}

class _PartnerSmsComposeScreenState extends State<PartnerSmsComposeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  final TextEditingController _manualPhonesCtrl = TextEditingController();
  final Set<String> _selected = {};

  bool _loading = true;
  String? _error;
  String? _companyId;
  List<Partner> _partners = [];
  List<PartnerSmsContact> _contacts = [];
  List<FleetPartnerVehicleRow> _fleet = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(() => setState(() {}));
    _messageCtrl.addListener(() => setState(() {}));
    _manualPhonesCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _messageCtrl.dispose();
    _manualPhonesCtrl.dispose();
    super.dispose();
  }

  List<String> get _manualPhones => parseManualPhoneNumbers(_manualPhonesCtrl.text);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        setState(() {
          _loading = false;
          _error = 'Fant ikke bedrift.';
        });
        return;
      }
      final partners = await PartnerService.fetchPartners(companyId: cid);
      final fleet = await PartnerService.fetchCompanyFleet(cid);
      final portals = await PartnerService.fetchCompanyPortalAccounts(cid);
      final partnerById = {for (final p in partners) p.id: p};
      final contacts = <PartnerSmsContact>[];
      final seenPhones = <String>{};

      void addContact({
        required String id,
        required String partnerId,
        required String label,
        required String? phone,
        required String kind,
      }) {
        final p = phone?.trim();
        if (p == null || p.length < 8) return;
        final key = p.replaceAll(RegExp(r'\s+'), '');
        if (seenPhones.contains(key)) return;
        seenPhones.add(key);
        final partner = partnerById[partnerId];
        contacts.add(PartnerSmsContact(
          id: id,
          partnerId: partnerId,
          partnerName: partner?.name ?? 'Ukjent',
          label: label,
          phone: p,
          kind: kind,
        ));
      }

      for (final p in partners) {
        addContact(
          id: 'partner:${p.id}',
          partnerId: p.id,
          label: '${p.name} · bedrift',
          phone: p.phone,
          kind: 'company',
        );
      }
      for (final row in fleet) {
        final v = row.vehicle;
        final driver = v.driverName?.trim();
        final label = driver != null && driver.isNotEmpty
            ? '${v.unitCode} · $driver'
            : v.unitCode;
        addContact(
          id: 'vehicle:${v.id}',
          partnerId: row.partner.id,
          label: label,
          phone: v.phone,
          kind: 'vehicle',
        );
      }
      for (final a in portals) {
        if (!a.isActive) continue;
        final kind = a.isOwner ? 'portal_owner' : 'portal_driver';
        addContact(
          id: 'portal:${a.id}',
          partnerId: a.partnerId,
          label: '${a.username} · ${a.isOwner ? 'eier' : 'sjåfør'}',
          phone: a.phone,
          kind: kind,
        );
      }

      contacts.sort((a, b) {
        final c = a.partnerName.compareTo(b.partnerName);
        if (c != 0) return c;
        return a.label.compareTo(b.label);
      });

      if (mounted) {
        setState(() {
          _companyId = cid;
          _partners = partners;
          _contacts = contacts;
          _fleet = fleet;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  List<PartnerSmsContact> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      return c.partnerName.toLowerCase().contains(q) ||
          c.label.toLowerCase().contains(q) ||
          c.phone.contains(q);
    }).toList();
  }

  Map<String, List<PartnerSmsContact>> get _grouped {
    final map = <String, List<PartnerSmsContact>>{};
    for (final c in _filtered) {
      map.putIfAbsent(c.partnerName, () => []).add(c);
    }
    return map;
  }

  Future<void> _sendToPhones({
    required List<String> phones,
    required String title,
    List<String> labels = const [],
    bool skipConfirm = false,
  }) async {
    final cid = _companyId;
    final msg = _messageCtrl.text.trim();
    if (cid == null || msg.isEmpty || phones.isEmpty) return;

    if (!skipConfirm) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              ...List.generate(phones.length.clamp(0, 8), (i) {
                final label = i < labels.length ? labels[i] : phones[i];
                return Text('• $label', style: const TextStyle(fontSize: 12));
              }),
              if (phones.length > 8) Text('… og ${phones.length - 8} til'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    }

    setState(() => _sending = true);
    var queued = 0;
    var queueFailed = 0;
    String? firstQueueError;
    for (final phone in phones) {
      final result = await PartnerService.queuePartnerComposeSms(
        companyId: cid,
        phone: phone,
        message: msg,
      );
      if (result.success) {
        queued++;
      } else {
        queueFailed++;
        firstQueueError ??= result.error;
      }
    }

    Map<String, dynamic>? sveve;
    if (queued > 0) {
      sveve = await PartnerService.flushSmsOutbox();
    }

    if (mounted) {
      setState(() => _sending = false);
      if (queueFailed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              firstQueueError ??
                  '$queued lagt i kø, $queueFailed feilet — sjekk telefonnummer og tilgang til queue_sms',
            ),
          ),
        );
        return;
      }

      final sveveFailed = (sveve?['failed'] as num?)?.toInt() ?? 0;
      final sveveSent = (sveve?['sent'] as num?)?.toInt() ?? 0;
      final sveveError = sveve?['error'] as String?;
      final detail = sveve?['details'] as List<dynamic>?;
      String? sveveMsg;
      if (detail != null && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['error'] != null) {
          sveveMsg = '${first['error']}';
        }
      }

      if (sveveError != null) {
        final isNetwork = sveveError.contains('Failed to fetch') ||
            sveveError.contains('ClientException');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNetwork
                  ? '$queued SMS lagt i kø. Sending fra nettleser feilet — prøv hard refresh. '
                      'Meldingen sendes fortsatt når SMS-worker kjører (cron).'
                  : '$queued lagt i kø, men Sveve feilet: $sveveError',
            ),
          ),
        );
      } else if (sveveFailed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sveveMsg ??
                  '$queued i kø — $sveveSent sendt via Sveve, $sveveFailed feilet. '
                  'Sjekk avsendernavn «Mavi» og Sveve-saldo.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sveveSent > 0
                  ? '$sveveSent SMS sendt via Sveve'
                  : '$queued SMS lagt i kø (sendes straks via Sveve)',
            ),
          ),
        );
      }
    }
  }

  Future<void> _send({required List<PartnerSmsContact> targets}) async {
    await _sendToPhones(
      phones: targets.map((t) => t.phone).toList(),
      title: 'Send SMS til ${targets.length} mottaker${targets.length == 1 ? '' : 'e'}?',
      labels: targets.map((t) => '${t.label} (${t.phone})').toList(),
    );
  }

  Future<void> _sendManualPhones() async {
    final phones = _manualPhones;
    if (phones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv minst ett gyldig 8-sifret nummer')),
      );
      return;
    }
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv melding først')),
      );
      return;
    }
    await _sendToPhones(
      phones: phones,
      title: 'Send SMS til ${phones.length} egne nummer?',
      labels: phones.map((p) => p).toList(),
    );
  }

  Future<void> _sendCombined() async {
    final selected = _contacts.where((c) => _selected.contains(c.id)).toList();
    final manual = _manualPhones;
    final phones = <String>[];
    final labels = <String>[];
    final seen = <String>{};

    void add(String phone, String label) {
      final key = phone.replaceAll(RegExp(r'\s+'), '');
      if (seen.contains(key)) return;
      seen.add(key);
      phones.add(phone);
      labels.add(label);
    }

    for (final c in selected) {
      add(c.phone, '${c.label} (${c.phone})');
    }
    for (final p in manual) {
      add(p, p);
    }
    if (phones.isEmpty || _messageCtrl.text.trim().isEmpty) return;

    await _sendToPhones(
      phones: phones,
      title: 'Send SMS til ${phones.length} mottaker${phones.length == 1 ? '' : 'e'}?',
      labels: labels,
    );
  }

  Future<void> _sendOne(PartnerSmsContact c) async {
    if (_messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv melding under kontaktlisten først')),
      );
      return;
    }
    await _send(targets: [c]);
  }

  Future<void> _sendRouteCustomers(List<RoutePdfCustomer> customers) async {
    await _sendToPhones(
      phones: customers.map((c) => c.phoneDisplay).toList(),
      title: 'Send SMS til ${customers.length} kunde${customers.length == 1 ? '' : 'r'}?',
      labels: customers.map((c) => '${c.sequence}. ${c.name} (${c.phoneDisplay})').toList(),
      skipConfirm: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final manualCount = _manualPhones.length;
    final selectedCount = _selected.length;
    final totalRecipients = selectedCount + manualCount;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartnerHeroBanner(
          compact: true,
          title: 'SMS',
          subtitle: _loading
              ? 'Laster…'
              : 'Kontakter: ${_contacts.length} · Rute-kunder fra PDF på «Send SMS til kunder»',
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.sms_outlined, color: Colors.white, size: 28),
          ),
        ),
        TabBar(
          controller: _tabs,
          indicatorColor: DriftProTheme.primaryGreen,
          labelColor: DriftProTheme.primaryGreenDark,
          unselectedLabelColor: PartnerUi.mutedText(context),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Kontakter'),
            Tab(text: 'Send SMS til kunder'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildContactsTab(isDark, totalRecipients, manualCount, selectedCount),
              _companyId == null
                  ? const Center(child: Text('Laster…'))
                  : PartnerSmsRouteCustomersTab(
                      companyId: _companyId!,
                      fleet: _fleet,
                      messageCtrl: _messageCtrl,
                      sending: _sending,
                      onSend: _sendRouteCustomers,
                    ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }
    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Partner-SMS')),
      body: content,
    );
  }

  Widget _buildContactsTab(
    bool isDark,
    int totalRecipients,
    int manualCount,
    int selectedCount,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DriftProTheme.primaryGreen));
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Søk bedrift, MAVI, sjåfør eller telefon…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _selected.addAll(_filtered.map((c) => c.id))),
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('Velg synlige'),
              ),
              TextButton.icon(
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.deselect, size: 18),
                label: const Text('Fjern valg'),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              for (final entry in _grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                    ),
                  ),
                ),
                ...entry.value.map((c) {
                  final selected = _selected.contains(c.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: Checkbox(
                        value: selected,
                        activeColor: DriftProTheme.primaryGreen,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(c.id);
                          } else {
                            _selected.remove(c.id);
                          }
                        }),
                      ),
                      title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(c.phone),
                      trailing: IconButton(
                        tooltip: 'Send kun til denne',
                        icon: const Icon(Icons.send_outlined),
                        onPressed: _sending ? null : () => _sendOne(c),
                      ),
                      onTap: () => setState(() {
                        if (selected) {
                          _selected.remove(c.id);
                        } else {
                          _selected.add(c.id);
                        }
                      }),
                    ),
                  );
                }),
              ],
              if (_filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Ingen kontakter matcher søket.', textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'SMS til valgte kontakter / egne nummer',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                PartnerSmsMessageSection(
                  messageCtrl: _messageCtrl,
                  onChanged: () => setState(() {}),
                  minLines: 3,
                ),
                const SizedBox(height: 12),
                _buildContactsSendSection(isDark, totalRecipients, manualCount, selectedCount),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactsSendSection(
    bool isDark,
    int totalRecipients,
    int manualCount,
    int selectedCount,
  ) {
    final selectedContacts =
        _contacts.where((c) => _selected.contains(c.id)).toList(growable: false);
    final manualPhones = _manualPhones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Text(
          'Egne nummer (ikke registrert i systemet)',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.grey[200] : Colors.grey[900],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Skriv ett nummer per linje, eller flere adskilt med komma, semikolon eller mellomrom. '
          'Systemet finner alle gyldige norske nummer (8 siffer).',
          style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _manualPhonesCtrl,
          decoration: InputDecoration(
            hintText: 'F.eks.\n91234567\n93456789, 99887766',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            suffixIcon: manualPhones.isNotEmpty
                ? IconButton(
                    tooltip: 'Tøm nummer',
                    onPressed: () => _manualPhonesCtrl.clear(),
                    icon: const Icon(Icons.clear),
                  )
                : null,
          ),
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.phone,
        ),
        if (manualPhones.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: manualPhones
                .map(
                  (p) => Chip(
                    label: Text(p),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      final lines = _manualPhonesCtrl.text
                          .split(RegExp(r'[\n\r]+'))
                          .map((l) => l.trim())
                          .where((l) => l.isNotEmpty)
                          .toList();
                      lines.removeWhere((l) => parseManualPhoneNumbers(l).contains(p));
                      _manualPhonesCtrl.text = lines.join('\n');
                    },
                  ),
                )
                .toList(),
          ),
          Text(
            '${manualPhones.length} nummer funnet',
            style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context)),
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _sending || manualPhones.isEmpty || _messageCtrl.text.trim().isEmpty
              ? null
              : _sendManualPhones,
          icon: const Icon(Icons.dialpad),
          label: Text('Send til egne nummer (${manualPhones.length})'),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kontakter: $selectedCount · Egne nummer: $manualCount',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (selectedContacts.isEmpty && manualPhones.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Velg kontakter over og/eller skriv egne nummer. '
                      'For rute-kunder fra PDF, bruk fanen «Send SMS til kunder».',
                      style: TextStyle(color: PartnerUi.mutedText(context)),
                    ),
                  )
                else ...[
                  if (selectedContacts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Fra kontaktliste:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ...selectedContacts.take(6).map(
                          (c) => Text('• ${c.label} (${c.phone})', style: const TextStyle(fontSize: 12)),
                        ),
                    if (selectedContacts.length > 6)
                      Text('… og ${selectedContacts.length - 6} til', style: const TextStyle(fontSize: 12)),
                  ],
                  if (manualPhones.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Egne nummer:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ...manualPhones.take(6).map((p) => Text('• $p', style: const TextStyle(fontSize: 12))),
                    if (manualPhones.length > 6)
                      Text('… og ${manualPhones.length - 6} til', style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _sending || totalRecipients == 0 || _messageCtrl.text.trim().isEmpty
              ? null
              : _sendCombined,
          style: FilledButton.styleFrom(
            backgroundColor: DriftProTheme.primaryGreen,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send),
          label: Text('Send til alle valgte ($totalRecipients)'),
        ),
        if (selectedCount > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _sending || selectedContacts.isEmpty || _messageCtrl.text.trim().isEmpty
                ? null
                : () => _send(targets: selectedContacts),
            icon: const Icon(Icons.contacts_outlined),
            label: Text('Kun valgte kontakter ($selectedCount)'),
          ),
        ],
      ],
    );
  }
}
