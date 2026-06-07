import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/email/email_log_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/email_log_entry.dart';
import '../../../models/email_log_filters.dart';
import 'notification_log_toolbar.dart';

/// Superadmin: utgående e-post (ikkesvar@driftpro.no).
class EmailOutboxLogPanel extends StatefulWidget {
  const EmailOutboxLogPanel({super.key});

  @override
  State<EmailOutboxLogPanel> createState() => _EmailOutboxLogPanelState();
}

class _EmailOutboxLogPanelState extends State<EmailOutboxLogPanel> {
  final _search = TextEditingController();
  final _recipient = TextEditingController();
  final _scroll = ScrollController();
  final List<EmailLogEntry> _items = [];
  EmailLogFilters _filters = const EmailLogFilters();
  bool _loading = true;
  int _total = 0;
  bool _filtersOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
          !_loading &&
          _items.length < _total) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _recipient.dispose();
    _scroll.dispose();
    super.dispose();
  }

  EmailLogFilters get _f => EmailLogFilters(
        search: _search.text,
        category: _filters.category,
        status: _filters.status,
        fromDate: _filters.fromDate,
        toDate: _filters.toDate,
        recipient: _recipient.text,
      );

  Future<void> _load({bool refresh = false}) async {
    if (refresh) setState(() => _loading = true);
    try {
      final r = await Future.wait([
        EmailLogService.fetchLog(limit: 40, offset: 0, filters: _f),
        EmailLogService.countLog(filters: _f),
      ]);
      if (mounted) {
        setState(() {
          if (refresh) _items.clear();
          _items.addAll(r[0] as List<EmailLogEntry>);
          _total = r[1] as int;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('E-post-logg: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    final batch = await EmailLogService.fetchLog(
      limit: 40,
      offset: _items.length,
      filters: _f,
    );
    if (mounted) setState(() => _items.addAll(batch));
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NotificationLogToolbar(
                totalCount: _total,
                onRefresh: () => _load(refresh: true),
                queueFilterActive: _filters.status,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(_filtersOpen ? 'Skjul' : 'Filter'),
                ),
              ),
            ],
          ),
        ),
        if (_filtersOpen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Søk emne/tekst',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(refresh: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _recipient,
                  decoration: const InputDecoration(
                    labelText: 'Mottaker e-post',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(refresh: true),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => _load(refresh: true), child: const Text('Søk')),
                const SizedBox(height: 8),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _chip('Alle', () => setState(() => _filters = const EmailLogFilters()), _filters.status == null),
              _chip('Sendt', () => setState(() => _filters = const EmailLogFilters(status: 'sendt')), _filters.status == 'sendt'),
              _chip('I kø', () => setState(() => _filters = const EmailLogFilters(status: 'i_ko')), _filters.status == 'i_ko'),
              _chip('Feilet', () => setState(() => _filters = const EmailLogFilters(status: 'feilet')), _filters.status == 'feilet'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final e = _items[i];
                    final color = e.deliveryStatus == 'sendt'
                        ? Colors.green
                        : e.deliveryStatus == 'feilet'
                            ? Colors.red
                            : Colors.orange;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: Icon(Icons.email_outlined, color: color),
                        title: Text(e.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${e.recipientName} · ${e.statusLabel} · ${df.format(e.createdAt)}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Til: ${e.toEmail}', style: const TextStyle(fontSize: 12)),
                                Text('Fra: ${e.senderName}', style: const TextStyle(fontSize: 12)),
                                if (e.description != null) Text('Beskrivelse: ${e.description}'),
                                Text('Emne: ${e.subject}'),
                                const SizedBox(height: 6),
                                Text(e.body, style: const TextStyle(fontSize: 13)),
                                if (e.errorMessage != null)
                                  Text('Feil: ${e.errorMessage}', style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback onTap, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          onTap();
          _load(refresh: true);
        },
      ),
    );
  }
}
