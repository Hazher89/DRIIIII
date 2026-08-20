import 'package:flutter/material.dart';

import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/route_pdf_text_service.dart';
import '../../core/services/sms/sms_phone_utils.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import 'widgets/partner_sms_message_section.dart';
import 'widgets/partner_sms_route_customers_tab.dart';
import 'widgets/partner_ui.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../core/layout/web_layout.dart';

class PartnerSmsContact {
  final String id;
  final String partnerId;
  final String partnerName;
  final String label;
  final String phone;
  final String kind;
  final String? maviCode;
  final String? vehicleId;

  const PartnerSmsContact({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.label,
    required this.phone,
    required this.kind,
    this.maviCode,
    this.vehicleId,
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
  final bool hubEmbedded;

  const PartnerSmsComposeScreen({
    super.key,
    this.embedded = false,
    this.hubEmbedded = false,
  });

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
  List<PartnerSmsContact> _contacts = [];
  List<FleetPartnerVehicleRow> _fleet = [];
  bool _sending = false;
  String? _selectedMaviGroup;
  String? _selectedVehicleId;
  int _hubTab = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
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
      final fleet = PartnerService.filterMaviFleetOnly(
        await PartnerService.fetchCompanyFleet(cid),
      );
      final portals = await PartnerService.fetchCompanyPortalAccounts(cid);
      final partnerById = {for (final p in partners) p.id: p};
      final vehicleToMavi = {
        for (final row in fleet)
          row.vehicle.id: MaviUnitCodes.normalize(row.vehicle.unitCode),
      };
      final contacts = <PartnerSmsContact>[];
      final seenPhones = <String>{};

      void addContact({
        required String id,
        required String partnerId,
        required String label,
        required String? phone,
        required String kind,
        required String maviCode,
        String? vehicleId,
      }) {
        final norm = normalizePhoneNo(phone ?? '');
        if (norm == null) return;
        if (seenPhones.contains(norm)) return;
        seenPhones.add(norm);
        final partner = partnerById[partnerId];
        contacts.add(PartnerSmsContact(
          id: id,
          partnerId: partnerId,
          partnerName: partner?.name ?? 'Ukjent',
          label: label,
          phone: displayPhoneNo(norm),
          kind: kind,
          maviCode: maviCode,
          vehicleId: vehicleId,
        ));
      }

      for (final row in fleet) {
        final v = row.vehicle;
        final mavi = MaviUnitCodes.normalize(v.unitCode);
        final partner = row.partner;
        final driver = v.driverName?.trim();
        final driverLabel = driver != null && driver.isNotEmpty
            ? '${MaviUnitCodes.compactLabel(mavi)} · $driver'
            : '${MaviUnitCodes.compactLabel(mavi)} · sjåfør';

        addContact(
          id: 'vehicle:${v.id}',
          partnerId: partner.id,
          label: driverLabel,
          phone: v.phone,
          kind: 'vehicle',
          maviCode: mavi,
          vehicleId: v.id,
        );
        addContact(
          id: 'partner:${partner.id}:v:${v.id}',
          partnerId: partner.id,
          label: '${partner.name} · bedrift',
          phone: partner.phone,
          kind: 'company',
          maviCode: mavi,
          vehicleId: v.id,
        );
      }

      for (final a in portals) {
        if (!a.isActive) continue;
        final kind = a.isOwner ? 'portal_owner' : 'portal_driver';
        final role = a.isOwner ? 'eier' : 'sjåfør';

        if (a.partnerVehicleId != null) {
          final mavi = vehicleToMavi[a.partnerVehicleId];
          if (mavi == null) continue;
          addContact(
            id: 'portal:${a.id}',
            partnerId: a.partnerId,
            label: '${a.username} · $role',
            phone: a.phone,
            kind: kind,
            maviCode: mavi,
            vehicleId: a.partnerVehicleId,
          );
          continue;
        }

        final partnerRows = fleet.where((r) => r.partner.id == a.partnerId);
        for (final row in partnerRows) {
          final mavi = vehicleToMavi[row.vehicle.id];
          if (mavi == null) continue;
          addContact(
            id: 'portal:${a.id}:v:${row.vehicle.id}',
            partnerId: a.partnerId,
            label: '${a.username} · $role',
            phone: a.phone,
            kind: kind,
            maviCode: mavi,
            vehicleId: row.vehicle.id,
          );
        }
      }

      contacts.sort((a, b) {
        final ma = a.maviCode ?? '';
        final mb = b.maviCode ?? '';
        final c = ma.compareTo(mb);
        if (c != 0) return c;
        return a.kind.compareTo(b.kind);
      });

      final groups = <String>{for (final c in contacts) c.maviCode ?? 'Uten MAVI'};
      final sortedGroups = groups.toList()..sort();

      if (mounted) {
        setState(() {
          _companyId = cid;
          _contacts = contacts;
          _fleet = fleet;
          _loading = false;
          _selectedVehicleId ??=
              fleet.isNotEmpty ? fleet.first.vehicle.id : null;
          _syncMaviFromVehicle();
          _selectedMaviGroup ??= sortedGroups.isNotEmpty ? sortedGroups.first : null;
          if (_selectedMaviGroup != null && !sortedGroups.contains(_selectedMaviGroup)) {
            _selectedMaviGroup = sortedGroups.isNotEmpty ? sortedGroups.first : null;
          }
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
      return (c.maviCode ?? '').toLowerCase().contains(q) ||
          MaviUnitCodes.compactLabel(c.maviCode ?? '').toLowerCase().contains(q) ||
          c.label.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.partnerName.toLowerCase().contains(q);
    }).toList();
  }

  Map<String, List<PartnerSmsContact>> get _maviGroups {
    final map = <String, List<PartnerSmsContact>>{};
    for (final c in _filtered) {
      final key = c.maviCode ?? 'Uten MAVI';
      map.putIfAbsent(key, () => []).add(c);
    }
    return map;
  }

  List<String> get _sortedMaviKeys {
    final keys = _maviGroups.keys.toList();
    keys.sort((a, b) {
      if (a == 'Uten MAVI') return 1;
      if (b == 'Uten MAVI') return -1;
      return a.compareTo(b);
    });
    return keys;
  }

  List<PartnerSmsContact> get _activeMaviContacts {
    final mavi = _selectedMaviCode;
    if (mavi == null || mavi.isEmpty) return const [];
    return _filtered.where((c) => c.maviCode == mavi).toList();
  }

  String? get _selectedMaviCode {
    final vid = _selectedVehicleId;
    if (vid != null) {
      for (final row in _fleet) {
        if (row.vehicle.id == vid) {
          return MaviUnitCodes.normalize(row.vehicle.unitCode);
        }
      }
    }
    return _selectedMaviGroup;
  }

  int _contactCountForVehicle(String vehicleId) {
    final mavi = _fleet
        .where((r) => r.vehicle.id == vehicleId)
        .map((r) => MaviUnitCodes.normalize(r.vehicle.unitCode))
        .firstOrNull;
    if (mavi == null) return 0;
    return _contacts.where((c) => c.maviCode == mavi).length;
  }

  String _maviGroupLabel(String mavi) {
    if (mavi == 'Uten MAVI') return 'Uten MAVI-bil';
    for (final row in _fleet) {
      if (MaviUnitCodes.normalize(row.vehicle.unitCode) == mavi) {
        final base = MaviUnitCodes.compactLabel(mavi);
        final driver = row.vehicle.driverName?.trim();
        if (driver != null && driver.isNotEmpty) return '$base · $driver';
        return base;
      }
    }
    return MaviUnitCodes.compactLabel(mavi);
  }

  String _maviFleetLabel(FleetPartnerVehicleRow row) {
    final m = MaviUnitCodes.compactLabel(row.vehicle.unitCode);
    final driver = row.vehicle.driverName?.trim();
    if (driver != null && driver.isNotEmpty) return '$m · $driver';
    return m;
  }

  void _syncMaviFromVehicle() {
    final vid = _selectedVehicleId;
    if (vid == null) return;
    for (final row in _fleet) {
      if (row.vehicle.id == vid) {
        _selectedMaviGroup = MaviUnitCodes.normalize(row.vehicle.unitCode);
        return;
      }
    }
  }

  List<FleetPartnerVehicleRow> get _sortedFleetRows {
    final copy = [..._fleet];
    copy.sort((a, b) {
      final c = a.vehicle.unitCode.compareTo(b.vehicle.unitCode);
      if (c != 0) return c;
      return (a.vehicle.driverName ?? '').compareTo(b.vehicle.driverName ?? '');
    });
    return copy;
  }

  Widget _buildSharedMaviPicker({EdgeInsets padding = const EdgeInsets.fromLTRB(16, 0, 16, 8)}) {
    if (_fleet.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          'Ingen MAVI-enheter i flåten. Registrer bil/sjåfør under Samarbeidspartnere.',
          style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context)),
        ),
      );
    }
    final sorted = _sortedFleetRows;
    final value = _selectedVehicleId != null &&
            sorted.any((r) => r.vehicle.id == _selectedVehicleId)
        ? _selectedVehicleId
        : sorted.first.vehicle.id;

    return Padding(
      padding: padding,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Velg MAVI-nummer',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: [
              for (final row in sorted)
                DropdownMenuItem(
                  value: row.vehicle.id,
                  child: Text(
                    '${_maviFleetLabel(row)}'
                    '${_contactCountForVehicle(row.vehicle.id) > 0 ? ' · ${_contactCountForVehicle(row.vehicle.id)} kontakt(er)' : ' · ingen telefon'}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
            onChanged: (v) => setState(() {
              _selectedVehicleId = v;
              _syncMaviFromVehicle();
            }),
          ),
        ),
      ),
    );
  }

  String _contactRoleLabel(PartnerSmsContact c) {
    return switch (c.kind) {
      'vehicle' => 'Sjåfør',
      'portal_owner' => 'Eier',
      'portal_driver' => 'Sjåfør (portal)',
      'company' => 'Bedrift',
      _ => 'Kontakt',
    };
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

    if (widget.hubEmbedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: DriftProLoadingCenter(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Steg 1 · Velg MAVI',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: DriftProTheme.primaryGreenDark,
                ),
              ),
            ),
            _buildSharedMaviPicker(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Kontakter'),
                    icon: Icon(Icons.contacts_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Rute-kunder'),
                    icon: Icon(Icons.route_outlined, size: 18),
                  ),
                ],
                selected: {_hubTab},
                onSelectionChanged: (s) => setState(() => _hubTab = s.first),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _hubTab == 0
                  ? KeyedSubtree(
                      key: const ValueKey('contacts'),
                      child: _buildContactsTab(
                        isDark,
                        totalRecipients,
                        manualCount,
                        selectedCount,
                        scrollable: true,
                        hideMaviPicker: true,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('route'),
                      child: _companyId == null
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: DriftProLoadingCenter(),
                            )
                          : PartnerSmsRouteCustomersTab(
                              companyId: _companyId!,
                              fleet: _fleet,
                              messageCtrl: _messageCtrl,
                              sending: _sending,
                              onSend: _sendRouteCustomers,
                              scrollable: true,
                              selectedVehicleId: _selectedVehicleId,
                              hideMaviPicker: true,
                              onVehicleChanged: (v) => setState(() {
                                _selectedVehicleId = v;
                                _syncMaviFromVehicle();
                              }),
                            ),
                    ),
            ),
          ],
        ],
      );
    }

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
          child: DriftProTabView(
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
    int selectedCount, {
    bool scrollable = false,
    bool hideMaviPicker = false,
  }) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }

    final maviKeys = _sortedMaviKeys;
    if (_selectedMaviGroup == null && maviKeys.isNotEmpty) {
      _selectedMaviGroup = maviKeys.first;
    }
    final selectedKey = _selectedMaviGroup;
    final groupContacts = _activeMaviContacts;
    final maviLabel = _selectedMaviCode != null
        ? MaviUnitCodes.compactLabel(_selectedMaviCode!)
        : 'MAVI';

    Widget contactList() {
      if (groupContacts.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.phone_disabled_outlined, size: 36, color: Colors.grey.shade500),
              const SizedBox(height: 8),
              Text(
                'Ingen telefon registrert for $maviLabel.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Legg inn telefon under Samarbeidspartner → bil, bedrift eller sjåfør-portal.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: PartnerUi.mutedText(context), height: 1.35),
              ),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hideMaviPicker)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Velg MAVI',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedKey != null && maviKeys.contains(selectedKey)
                        ? selectedKey
                        : maviKeys.first,
                    isExpanded: true,
                    items: [
                      for (final m in maviKeys)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            _maviGroupLabel(m),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _selectedMaviGroup = v),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hideMaviPicker
                        ? 'Steg 2 · ${groupContacts.length} kontakt(er) for $maviLabel'
                        : '${groupContacts.length} kontakt(er)',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selected.addAll(groupContacts.map((c) => c.id))),
                  child: const Text('Velg alle'),
                ),
                TextButton(
                  onPressed: groupContacts.every((c) => !_selected.contains(c.id))
                      ? null
                      : () => setState(() {
                            for (final c in groupContacts) {
                              _selected.remove(c.id);
                            }
                          }),
                  child: const Text('Fjern'),
                ),
              ],
            ),
          ),
          for (final c in groupContacts)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: ListTile(
                leading: Checkbox(
                  value: _selected.contains(c.id),
                  activeColor: DriftProTheme.primaryGreen,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(c.id);
                    } else {
                      _selected.remove(c.id);
                    }
                  }),
                ),
                title: Text(
                  _contactRoleLabel(c),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${c.label}\n${c.phone}'),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Send kun til denne',
                  icon: const Icon(Icons.send_outlined),
                  onPressed: _sending ? null : () => _sendOne(c),
                ),
                onTap: () => setState(() {
                  if (_selected.contains(c.id)) {
                    _selected.remove(c.id);
                  } else {
                    _selected.add(c.id);
                  }
                }),
              ),
            ),
        ],
      );
    }

    Widget maviSelector() => contactList();

    final messageBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          hideMaviPicker ? 'Steg 3 · Skriv melding' : 'Skriv melding',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: hideMaviPicker ? DriftProTheme.primaryGreenDark : null,
          ),
        ),
        const SizedBox(height: 8),
        PartnerSmsMessageSection(
          messageCtrl: _messageCtrl,
          onChanged: () => setState(() {}),
          minLines: 3,
        ),
        const SizedBox(height: 12),
        _buildContactsSendSection(
          isDark,
          totalRecipients,
          manualCount,
          selectedCount,
          hideMaviPicker: hideMaviPicker,
        ),
      ],
    );

    final searchRow = hideMaviPicker
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.fromLTRB(16, scrollable ? 0 : 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Søk MAVI-nummer eller telefon…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (_) {
                final keys = _sortedMaviKeys;
                if (keys.isNotEmpty &&
                    (_selectedMaviGroup == null || !keys.contains(_selectedMaviGroup))) {
                  setState(() => _selectedMaviGroup = keys.first);
                } else {
                  setState(() {});
                }
              },
            ),
          );

    if (scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          searchRow,
          contactList(),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: messageBlock),
        ],
      );
    }

    return Column(
      children: [
        searchRow,
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: maviSelector(),
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: messageBlock,
          ),
        ),
      ],
    );
  }

  Widget _buildContactsSendSection(
    bool isDark,
    int totalRecipients,
    int manualCount,
    int selectedCount, {
    bool hideMaviPicker = false,
  }) {
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
                      'For rute-kunder fra PDF, bytt til «Rute-kunder» over.',
                      style: TextStyle(color: PartnerUi.mutedText(context)),
                    ),
                  )
                else ...[
                  if (selectedContacts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Fra kontaktliste:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ...selectedContacts.take(6).map(
                          (c) => Text(
                            '• ${_contactRoleLabel(c)} (${c.maviCode != null ? MaviUnitCodes.compactLabel(c.maviCode!) : '?'}) · ${c.phone}',
                            style: const TextStyle(fontSize: 12),
                          ),
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
        Text(
          hideMaviPicker ? 'Steg 4 · Send' : 'Send',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: hideMaviPicker ? DriftProTheme.primaryGreenDark : null,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _sending || totalRecipients == 0 || _messageCtrl.text.trim().isEmpty
              ? null
              : _sendCombined,
          style: FilledButton.styleFrom(
            backgroundColor: DriftProTheme.primaryGreen,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _sending
              ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
              : const Icon(Icons.send),
          label: Text('Send SMS ($totalRecipients)'),
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
