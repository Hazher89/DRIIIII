import 'package:flutter/material.dart';

import '../../../core/services/chat/chat_advanced_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import 'chat_ui_helpers.dart';

class ChatPinnedMessageBar extends StatelessWidget {
  const ChatPinnedMessageBar({
    super.key,
    required this.message,
    required this.onTap,
    required this.onUnpin,
  });

  final ChatMessage message;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 18, color: DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Festet melding · ${message.senderName ?? ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      ChatUiHelpers.replySnippet(message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onUnpin),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatRulesBanner extends StatelessWidget {
  const ChatRulesBanner({super.key, required this.rules, required this.onDismiss});

  final String rules;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.rule, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(rules, style: const TextStyle(fontSize: 12))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}

class ChatOnlineStrip extends StatelessWidget {
  const ChatOnlineStrip({super.key, required this.users});

  final List<ChatOnlineUser> users;

  @override
  Widget build(BuildContext context) {
    final online = users.where((u) => u.isOnline).toList();
    if (online.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Wrap(
        spacing: 6,
        children: [
          for (final u in online.take(8))
            Chip(
              avatar: CircleAvatar(
                radius: 8,
                backgroundColor: Colors.green.shade400,
                child: const SizedBox(width: 6, height: 6),
              ),
              label: Text(u.fullName, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
