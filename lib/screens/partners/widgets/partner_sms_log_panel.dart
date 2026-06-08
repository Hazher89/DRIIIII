import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_sms_log_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner_sms_log_entry.dart';
import '../../../models/partner_sms_log_filters.dart';
import 'partner_ui.dart';
import '../../profile/widgets/notification_log_toolbar.dart';

/// SMS-logg kun for samarbeid-modulen (RPC filtrerer bort HMS/fravær/avvik).
class PartnerSmsLogPanel extends StatefulWidget {
  final List<Partner> partners;

  const PartnerSmsLogPanel({super.key, required this.partners});

  @override
  State<PartnerSmsLogPanel> createState() => _PartnerSmsLogPanelState();
}

class _PartnerSmsLogPanelState extends State<PartnerSmsLogPanel> {
  final _messageSearch = TextEditingController();
  final _recipient = TextEditingController();
  final _sender = TextEditingController();
  final _phone = TextEditingController();
  final _scroll = ScrollController();

  final List<PartnerSmsLogEntry> _items = [];
  PartnerSmsLogFilters _filters = const PartnerSmsLogFilters();
  bool _loading = true;
  bool _loadingMore = false;
  int _totalCount = 0;
  bool _filtersExpanded = false;
  static const _pageSize = 40;

  static const _sortOptions = <String, String>{
    'created_desc': 'Nyeste først',
    'created_asc': 'Eldste først',
    'sent_desc': 'Sist sendt',
    'recipient_asc': 'Mottaker A–Å',
    'recipient_desc': 'Mottaker Å–A',
  };

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageSearch.dispose();
    _recipient.dispose();
    _sender.dispose();
    _phone.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  PartnerSmsLogFilters get _currentFilters => PartnerSmsLogFilters(
        search: _messageSearch.text,
        category: _filters.category,
        status: _filters.status,
        fromDate: _filters.fromDate,
        toDate: _filters.toDate,
        recipient: _recipient.text,
        sender: _sender.text,
        phone: _phone.text,
        partnerId: _filters.partnerId,
        sort: _filters.sort,
      );

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _items.clear();
      });
    }
    final f = _currentFilters;
    try {
      final results = await Future.wait([
        PartnerSmsLogService.fetchLog(limit: _pageSize, offset: 0, filters: f),
        PartnerSmsLogService.countLog(filters: f),
      ]);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(results[0] as List<PartnerSmsLogEntry>);
          _totalCount = results[1] as int;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke hente SMS-logg: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    if (_items.length >= _totalCount) return;
    setState(() => _loadingMore = true);
    try {
      final batch = await PartnerSmsLogService.fetchLog(
        limit: _pageSize,
        offset: _items.length,
        filters: _currentFilters,
      );
      if (mounted) {
        setState(() {
          _items.addAll(batch);
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _clearFilters() {
    _messageSearch.clear();
    _recipient.clear();
    _sender.clear();
    _phone.clear();
    setState(() => _filters = const PartnerSmsLogFilters());
    _load(refresh: true);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_filters.fromDate ?? DateTime.now())
        : (_filters.toDate ?? DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() {
      _filters = isFrom
          ? _filters.copyWith(fromDate: d)
          : _filters.copyWith(toDate: d);
    });
    _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final sortedPartners = List<Partner>.from(widget.partners)
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartnerHeroBanner(
          compact: true,
          title: 'SMS-logg',
          subtitle:
              'Kun utgående SMS fra samarbeid (ruter, portal, møter, manuell). HMS og fravær vises ikke her.',
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history, color: Colors.white, size: 26),
          ),
        ),
        Material(
          color: isDark ? DriftProTheme.cardDark : Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NotificationLogToolbar(
                        totalCount: _totalCount,
                        onRefresh: () => _load(refresh: true),
                        partnerScopeOnly: true,
                        queueFilterActive: _filters.status,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _filtersExpanded = !_filtersExpanded),
                      icon: Icon(_filtersExpanded ? Icons.expand_less : Icons.tune),
                      label: Text(_filtersExpanded ? 'Skjul' : 'Filter'),
                    ),
                  ],
                ),
                if (_filtersExpanded) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageSearch,
                    decoration: const InputDecoration(
                      labelText: 'Søk melding / MAVI / bedrift',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(refresh: true),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(
                      labelText: 'Bedrift (samarbeidspartner)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    initialValue: _filters.partnerId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Alle bedrifter'),
                      ),
                      for (final p in sortedPartners)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _filters = _filters.copyWith(
                            partnerId: v,
                            clearPartner: v == null,
                          ));
                      _load(refresh: true);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Sortering',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    initialValue: _filters.sort,
                    items: [
                      for (final e in _sortOptions.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _filters = _filters.copyWith(sort: v));
                      _load(refresh: true);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _recipient,
                          decoration: const InputDecoration(
                            labelText: 'Mottaker',
                            prefixIcon: Icon(Icons.person_outline),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _load(refresh: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _sender,
                          decoration: const InputDecoration(
                            labelText: 'Utløst av',
                            prefixIcon: Icon(Icons.send_outlined),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _load(refresh: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefonnummer',
                      prefixIcon: Icon(Icons.phone_outlined),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(refresh: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            _filters.fromDate == null
                                ? 'Fra dato'
                                : DateFormat('dd.MM.yyyy').format(_filters.fromDate!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.date_range, size: 18),
                          label: Text(
                            _filters.toDate == null
                                ? 'Til dato'
                                : DateFormat('dd.MM.yyyy').format(_filters.toDate!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _load(refresh: true),
                          child: const Text('Søk'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearFilters,
                        child: const Text('Nullstill'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _statusChip('Alle', null, _filters.status == null && _filters.category == null),
              _statusChip('Sendt', 'sendt', _filters.status == 'sendt'),
              _statusChip('I kø', 'i_ko', _filters.status == 'i_ko'),
              _statusChip('Feilet', 'feilet', _filters.status == 'feilet'),
              _catChip('Rute sjåfør', 'partner_route'),
              _catChip('Rute bil-eier', 'partner_route_owner'),
              _catChip('Manuell', 'partner_compose'),
              _catChip('Portal', 'partner_portal'),
              _catChip('Møte', 'partner_meeting'),
              _catChip('Bilutleie', 'vehicle_rental'),
              _catChip('Utleie status', 'vehicle_rental_status'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Ingen SMS i samarbeidsloggen for valgt filter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PartnerUi.mutedText(context)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(refresh: true),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _logCard(_items[i], df);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _statusChip(String label, String? value, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) {
          setState(() {
            if (value == null) {
              _filters = _filters.copyWith(clearStatus: true, clearCategory: true);
            } else {
              _filters = _filters.copyWith(
                status: selected ? null : value,
                clearCategory: true,
              );
            }
          });
          _load(refresh: true);
        },
      ),
    );
  }

  Widget _catChip(String label, String value) {
    final selected = _filters.category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _filters = _filters.copyWith(
              category: selected ? null : value,
              clearStatus: true,
            );
          });
          _load(refresh: true);
        },
      ),
    );
  }

  Widget _logCard(PartnerSmsLogEntry e, DateFormat df) {
    Color statusColor;
    switch (e.deliveryStatus) {
      case 'sendt':
        statusColor = DriftProTheme.success;
        break;
      case 'feilet':
        statusColor = DriftProTheme.error;
        break;
      default:
        statusColor = DriftProTheme.warning;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showDetail(e, df),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sms_outlined, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.categoryLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      e.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (e.contextLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  e.contextLabel!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
              if (e.partnerName != null && e.partnerName!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  e.partnerName!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                e.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.bodySm,
              ),
              const SizedBox(height: 10),
              _meta(Icons.schedule, 'Kø', df.format(e.createdAt.toLocal())),
              if (e.sentAt != null)
                _meta(Icons.check_circle_outline, 'Sendt', df.format(e.sentAt!.toLocal())),
              _meta(Icons.person_outline, 'Til', '${e.recipientName} · ${e.toPhone}'),
              _meta(Icons.send_outlined, 'Avsender', e.senderName),
              _meta(Icons.touch_app_outlined, 'Utløst av', e.triggeredByName),
              if (e.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Feil: ${e.errorMessage}',
                    style: TextStyle(color: DriftProTheme.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text('$label:', style: DriftProTheme.caption),
          ),
          Expanded(child: Text(value, style: DriftProTheme.caption)),
        ],
      ),
    );
  }

  void _showDetail(PartnerSmsLogEntry e, DateFormat df) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ListView(
            controller: scroll,
            children: [
              Text('SMS-detaljer', style: DriftProTheme.headingSm),
              const SizedBox(height: 12),
              _detailRow('Status', e.statusLabel),
              _detailRow('Kategori', e.categoryLabel),
              if (e.contextLabel != null) _detailRow('Kontekst', e.contextLabel!),
              if (e.partnerName != null) _detailRow('Bedrift', e.partnerName!),
              _detailRow('Avsender (Sveve)', e.senderName),
              _detailRow('Mottaker', e.recipientName),
              _detailRow('Telefon', e.toPhone),
              _detailRow('Utløst av', e.triggeredByName),
              _detailRow('Opprettet i kø', df.format(e.createdAt.toLocal())),
              if (e.sentAt != null) _detailRow('Sendt', df.format(e.sentAt!.toLocal())),
              if (e.sveveMessageId != null) _detailRow('Sveve ID', '${e.sveveMessageId}'),
              if (e.referenceType != null)
                _detailRow('Referanse', '${e.referenceType} ${e.referenceId ?? ""}'),
              const Divider(height: 24),
              Text('Melding', style: DriftProTheme.labelMd),
              const SizedBox(height: 8),
              SelectableText(e.message),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: DriftProTheme.caption)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
