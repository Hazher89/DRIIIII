import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import '../../../models/user_profile.dart';

/// Superadmin/moderator: audit-logg og global blokkering.
class ChatModerationScreen extends StatefulWidget {
  const ChatModerationScreen({
    super.key,
    required this.profile,
  });

  final UserProfile profile;

  @override
  State<ChatModerationScreen> createState() => _ChatModerationScreenState();
}

class _ChatModerationScreenState extends State<ChatModerationScreen> {
  List<ChatAuditEntry> _audit = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final audit = await PartnerChatService.fetchModerationAudit();
      if (!mounted) return;
      setState(() {
        _audit = audit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste moderering: $e')),
      );
    }
  }

  Future<void> _blockUser() async {
    final userIdCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Blokker bruker globalt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Bruker-ID (UUID)',
                hintText: 'Lim inn profil-ID',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Årsak (valgfritt)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Blokker')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PartnerChatService.adminBlockUser(
        userIdCtrl.text.trim(),
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bruker blokkert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    } finally {
      userIdCtrl.dispose();
      reasonCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat-moderering'),
        actions: [
          IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _blockUser,
        icon: const Icon(Icons.block),
        label: const Text('Blokker bruker'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _audit.isEmpty
              ? Center(
                  child: Text(
                    'Ingen modereringshendelser ennå.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _audit.length,
                    itemBuilder: (_, i) {
                      final a = _audit[i];
                      final when = a.createdAt != null
                          ? DateFormat('d.M.y HH:mm', 'nb').format(a.createdAt!)
                          : '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                            child: Icon(Icons.shield_outlined, color: DriftProTheme.primaryGreen),
                          ),
                          title: Text(a.actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            [
                              if (when.isNotEmpty) when,
                              if (a.targetUserId != null) 'Bruker: ${a.targetUserId!.substring(0, 8)}…',
                              if (a.roomId != null) 'Rom: ${a.roomId!.substring(0, 8)}…',
                            ].join('\n'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
