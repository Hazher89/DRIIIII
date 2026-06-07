import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/notification/notification_audit_service.dart';
import '../../../core/services/notification/notification_log_admin_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/notification_audit_entry.dart';

/// Logg over varsler som ikke ble sendt (eller lagt i kø).
class NotificationAuditPanel extends StatefulWidget {
  const NotificationAuditPanel({
    super.key,
    this.partnerScopeOnly = false,
  });

  final bool partnerScopeOnly;

  @override
  State<NotificationAuditPanel> createState() => _NotificationAuditPanelState();
}

class _NotificationAuditPanelState extends State<NotificationAuditPanel> {
  final List<NotificationAuditEntry> _items = [];
  bool _loading = true;
  String? _channel;
  String _status = 'skipped';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await NotificationAuditService.fetch(
        limit: 80,
        channel: _channel,
        status: _status,
        partnerScope: widget.partnerScopeOnly ? true : null,
      );
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(list);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audit: $e')),
        );
      }
    }
  }

  Future<void> _clearAudit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tøm audit-logg?'),
        content: const Text(
          'Sletter alle «Ikke sendt»/audit-rader for bedriften. Kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await NotificationLogAdminService.clearLogs(
        sms: false,
        email: false,
        audit: true,
        partnerScopeOnly: widget.partnerScopeOnly,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audit-logg tømt (${r.auditDeleted} rader)')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke tømme: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Ikke sendt'),
                selected: _status == 'skipped',
                onSelected: (_) {
                  setState(() => _status = 'skipped');
                  _load();
                },
              ),
              FilterChip(
                label: const Text('I kø'),
                selected: _status == 'queued',
                onSelected: (_) {
                  setState(() => _status = 'queued');
                  _load();
                },
              ),
              FilterChip(
                label: const Text('SMS'),
                selected: _channel == 'sms',
                onSelected: (_) {
                  setState(() => _channel = _channel == 'sms' ? null : 'sms');
                  _load();
                },
              ),
              FilterChip(
                label: const Text('E-post'),
                selected: _channel == 'email',
                onSelected: (_) {
                  setState(() => _channel = _channel == 'email' ? null : 'email');
                  _load();
                },
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              IconButton(
                tooltip: 'Tøm audit-logg',
                onPressed: _clearAudit,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('Ingen hendelser i utvalget'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final a = _items[i];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              a.eventChannel == 'sms'
                                  ? Icons.sms_failed_outlined
                                  : Icons.mark_email_unread_outlined,
                              color: Colors.orange,
                            ),
                            title: Text(
                              '${a.channelLabel} — ${a.deliveryStatusLabel}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${a.messagePreview ?? a.description ?? a.category ?? 'Varself'}\n'
                              'Til: ${a.recipient} · ${df.format(a.createdAt)}'
                              '${a.partnerName != null ? '\nBedrift: ${a.partnerName}' : ''}'
                              '${a.deliveryStatus == 'skipped' ? '\n${a.skipReasonLabel}' : ''}',
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
