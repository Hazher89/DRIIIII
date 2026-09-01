import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';

/// Farge og initialer per avsender — konsistent i hele chatten.
abstract final class ChatUiHelpers {
  static const _palette = [
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFFEF6C00),
    Color(0xFF00838F),
    Color(0xFF4527A0),
    Color(0xFFAD1457),
  ];

  static Color senderColor(String userId) {
    var hash = 0;
    for (final c in userId.codeUnits) {
      hash = (hash + c) % 100000;
    }
    return _palette[hash % _palette.length];
  }

  static String initials(String? name) {
    final parts = (name ?? 'B').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static String formatMessageTime(DateTime dt) => DateFormat('HH:mm', 'nb').format(dt);

  static String formatDayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'I dag';
    if (day == today.subtract(const Duration(days: 1))) return 'I går';
    return DateFormat('EEEE d. MMM', 'nb').format(dt);
  }

  static bool shouldShowDateHeader(DateTime current, DateTime? previous) {
    if (previous == null) return true;
    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  static String mediaPreviewLabel(ChatMessage msg) {
    if (msg.body.trim().isNotEmpty) return msg.body.trim();
    return switch (msg.messageType) {
      ChatMessageType.video => '🎬 Video',
      ChatMessageType.image => '📷 Bilde',
      _ => 'Vedlegg',
    };
  }

  static String replySnippet(ChatMessage msg) {
    if (msg.body.trim().isNotEmpty) return msg.body.trim();
    if (msg.attachments.isNotEmpty) {
      final att = msg.attachments.first;
      if (att.isVideo || msg.messageType == ChatMessageType.video) return 'Video';
      if (att.isImage || msg.messageType == ChatMessageType.image) return 'Bilde';
    }
    return mediaPreviewLabel(msg);
  }
}

/// Avatar med initialer og fargekode.
class ChatSenderAvatar extends StatelessWidget {
  const ChatSenderAvatar({
    super.key,
    required this.name,
    required this.userId,
    this.radius = 18,
    this.mine = false,
  });

  final String? name;
  final String userId;
  final double radius;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final color = mine ? DriftProTheme.primaryGreen : ChatUiHelpers.senderColor(userId);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Text(
        ChatUiHelpers.initials(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.78,
        ),
      ),
    );
  }
}

/// Datoseparator mellom meldingsdager.
class ChatDateHeader extends StatelessWidget {
  const ChatDateHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
