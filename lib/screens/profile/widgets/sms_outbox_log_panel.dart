import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/sms/sms_log_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/sms_log_entry.dart';
import '../../../models/sms_log_filters.dart';

/// Superadmin: alle utgående SMS med avansert søk.
class SmsOutboxLogPanel extends StatefulWidget {
  const SmsOutboxLogPanel({super.key});

  @override
  State<SmsOutboxLogPanel> createState() => _SmsOutboxLogPanelState();
}

class _SmsOutboxLogPanelState extends State<SmsOutboxLogPanel> {
  final _messageSearch = TextEditingController();
  final _recipient = TextEditingController();
  final _sender = TextEditingController();
  final _phone = TextEditingController();
  final _scroll = ScrollController();

  final List<SmsLogEntry> _items = [];
  SmsLogFilters _filters = const SmsLogFilters();
  bool _loading = true;
  bool _loadingMore = false;
  int _totalCount = 0;
  bool _filtersExpanded = false;
  static const _pageSize = 40;

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

  SmsLogFilters get _currentFilters => SmsLogFilters(
        search: _messageSearch.text,
        category: _filters.category,
        status: _filters.status,
        fromDate: _filters.fromDate,
        toDate: _filters.toDate,
        recipient: _recipient.text,
        sender: _sender.text,
        phone: _phone.text,
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
        SmsLogService.fetchLog(limit: _pageSize, offset: 0, filters: f),
        SmsLogService.countLog(filters: f),
      ]);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(results[0] as List<SmsLogEntry>);
          _totalCount = results[1] as int;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke hente SMS: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading) return;
    if (_items.length >= _totalCount) return;
    setState(() => _loadingMore = true);
    try {
      final batch = await SmsLogService.fetchLog(
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
    setState(() => _filters = const SmsLogFilters());
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

    return Column(
      children: [
        Material(
          color: isDark ? DriftProTheme.cardDark : Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_totalCount SMS i utvalg',
                        style: DriftProTheme.labelMd,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _filtersExpanded = !_filtersExpanded),
                      icon: Icon(
                        _filtersExpanded
                            ? Icons.expand_less
                            : Icons.tune,
                      ),
                      label: Text(_filtersExpanded ? 'Skjul filter' : 'Filter'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _load(refresh: true),
                    ),
                  ],
                ),
                if (_filtersExpanded) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageSearch,
                    decoration: const InputDecoration(
                      labelText: 'Søk i meldingstekst',
                      prefixIcon: Icon(Icons.message_outlined),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _load(refresh: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _recipient,
                          decoration: const InputDecoration(
                            labelText: 'Mottaker (navn/tlf)',
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
                            labelText: 'Avsender / utløst av',
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
                                : DateFormat('dd.MM.yyyy')
                                    .format(_filters.fromDate!),
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
                                : DateFormat('dd.MM.yyyy')
                                    .format(_filters.toDate!),
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
              _catChip('Fravær', 'absence_request'),
              _catChip('Avvik', 'ticket'),
              _catChip('Utstyr', 'equipment_reminder'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('Ingen SMS matcher filteret'))
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
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
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
        label: Text(label),
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
        label: Text(label),
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

  Widget _logCard(SmsLogEntry e, DateFormat df) {
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              const SizedBox(height: 6),
              Text(
                e.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.bodySm,
              ),
              const SizedBox(height: 10),
              _meta(Icons.schedule, 'Kø', df.format(e.createdAt)),
              if (e.sentAt != null)
                _meta(Icons.check_circle_outline, 'Sendt', df.format(e.sentAt!)),
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

  void _showDetail(SmsLogEntry e, DateFormat df) {
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
              _detailRow('Avsender (Sveve)', e.senderName),
              _detailRow('Mottaker', e.recipientName),
              _detailRow('Telefon', e.toPhone),
              _detailRow('Utløst av', e.triggeredByName),
              _detailRow('Opprettet i kø', df.format(e.createdAt)),
              if (e.sentAt != null)
                _detailRow('Sendt', df.format(e.sentAt!)),
              if (e.sveveMessageId != null)
                _detailRow('Sveve ID', '${e.sveveMessageId}'),
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
          SizedBox(
            width: 120,
            child: Text(label, style: DriftProTheme.caption),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
