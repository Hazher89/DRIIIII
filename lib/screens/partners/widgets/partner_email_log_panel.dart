import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_email_log_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/email_log_entry.dart';
import '../../../models/email_log_filters.dart';
import '../../../models/partner/partner.dart';
class PartnerEmailLogPanel extends StatefulWidget {
  const PartnerEmailLogPanel({super.key, required this.partners});

  final List<Partner> partners;

  @override
  State<PartnerEmailLogPanel> createState() => _PartnerEmailLogPanelState();
}

class _PartnerEmailLogPanelState extends State<PartnerEmailLogPanel> {
  final _search = TextEditingController();
  final List<EmailLogEntry> _items = [];
  EmailLogFilters _filters = const EmailLogFilters();
  bool _loading = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final f = EmailLogFilters(
        search: _search.text,
        status: _filters.status,
        partnerId: _filters.partnerId,
      );
      final r = await Future.wait([
        PartnerEmailLogService.fetchLog(filters: f),
        PartnerEmailLogService.countLog(filters: f),
      ]);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(r[0] as List<EmailLogEntry>);
          _total = r[1] as int;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Partner e-post: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('$_total e-poster', style: DriftProTheme.labelMd),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Søk',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        if (widget.partners.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                FilterChip(
                  label: const Text('Alle bedrifter'),
                  selected: _filters.partnerId == null,
                  onSelected: (_) {
                    setState(() => _filters = EmailLogFilters(status: _filters.status));
                    _load();
                  },
                ),
                ...widget.partners.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FilterChip(
                      label: Text(p.name, overflow: TextOverflow.ellipsis),
                      selected: _filters.partnerId == p.id,
                      onSelected: (_) {
                        setState(() => _filters = EmailLogFilters(
                              partnerId: p.id,
                              status: _filters.status,
                            ));
                        _load();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final e = _items[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: Text(e.contextLabel ?? e.displayTitle),
                        subtitle: Text(
                          '${e.partnerName ?? '—'} · ${e.toEmail}\n'
                          '${e.statusLabel} · ${df.format(e.createdAt)}',
                        ),
                        isThreeLine: true,
                        onTap: () => showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(e.subject),
                            content: SingleChildScrollView(child: Text(e.body)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Lukk'),
                              ),
                            ],
                          ),
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
