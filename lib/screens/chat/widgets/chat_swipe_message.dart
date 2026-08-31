import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';

/// Meldingsboble med swipe-for-svar og lang-trykk-meny.
class ChatSwipeMessage extends StatefulWidget {
  const ChatSwipeMessage({
    super.key,
    required this.message,
    required this.mine,
    required this.onReply,
    this.onOpenImage,
  });

  final ChatMessage message;
  final bool mine;
  final ValueChanged<ChatMessage> onReply;
  final void Function(String url)? onOpenImage;

  @override
  State<ChatSwipeMessage> createState() => _ChatSwipeMessageState();
}

class _ChatSwipeMessageState extends State<ChatSwipeMessage> with SingleTickerProviderStateMixin {
  double _drag = 0;
  late AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  void _onReply() => widget.onReply(widget.message);

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final m = widget.message;
    final threshold = mine ? -72.0 : 72.0;
    final showReplyHint = mine ? _drag < -24 : _drag > 24;

    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (mine) {
          setState(() => _drag = (_drag + d.delta.dx).clamp(-96.0, 0.0));
        } else {
          setState(() => _drag = (_drag + d.delta.dx).clamp(0.0, 96.0));
        }
      },
      onHorizontalDragEnd: (_) {
        if ((mine && _drag <= threshold) || (!mine && _drag >= threshold)) {
          _onReply();
        }
        setState(() => _drag = 0);
      },
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Svar'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _onReply();
                  },
                ),
                if (m.body.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Kopier tekst'),
                    onTap: () => Navigator.pop(ctx),
                  ),
              ],
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          if (showReplyHint)
            Positioned(
              right: mine ? 8 : null,
              left: mine ? null : 8,
              child: Icon(Icons.reply, color: DriftProTheme.primaryGreen.withValues(alpha: 0.8)),
            ),
          Transform.translate(
            offset: Offset(_drag, 0),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: _ChatBubbleBody(
                message: m,
                mine: mine,
                onOpenImage: widget.onOpenImage,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubbleBody extends StatelessWidget {
  const _ChatBubbleBody({
    required this.message,
    required this.mine,
    this.onOpenImage,
  });

  final ChatMessage message;
  final bool mine;
  final void Function(String url)? onOpenImage;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? DriftProTheme.primaryGreen : Colors.grey.shade200;
    final fg = mine ? Colors.white : Colors.black87;
    final time = DateFormat('HH:mm', 'nb').format(message.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: message.isBlocked ? Colors.red.shade100 : bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyTo != null) _ReplyPreview(reply: message.replyTo!, mine: mine),
          if (!mine && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.senderName!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: fg.withValues(alpha: 0.85),
                ),
              ),
            ),
          if (message.hasMedia) ...[
            for (final att in message.attachments) _AttachmentView(att: att, onOpen: onOpenImage),
            if (message.body.isNotEmpty) const SizedBox(height: 6),
          ],
          if (message.body.isNotEmpty)
            Text(
              message.isDeleted ? '[Slettet]' : message.body,
              style: TextStyle(color: fg, height: 1.35),
            ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time, style: TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.7))),
              if (message.isEdited) ...[
                const SizedBox(width: 6),
                Text('redigert', style: TextStyle(fontSize: 8, color: fg.withValues(alpha: 0.6))),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.reply, required this.mine});

  final ChatMessage reply;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final accent = mine ? Colors.white : DriftProTheme.primaryGreen;
    final preview = reply.hasMedia
        ? (reply.messageType == ChatMessageType.video ? '🎬 Video' : '📷 Bilde')
        : reply.body;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: mine ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.senderName ?? 'Svar',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent),
          ),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView({required this.att, this.onOpen});

  final ChatAttachment att;
  final void Function(String url)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (att.isImage && att.signedUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => onOpen?.call(att.signedUrl!),
          child: CachedNetworkImage(
            imageUrl: att.signedUrl!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              height: 120,
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => _mediaPlaceholder(Icons.broken_image_outlined, 'Bilde'),
          ),
        ),
      );
    }

    if (att.isVideo) {
      return _mediaPlaceholder(Icons.videocam_outlined, att.fileName ?? 'Video');
    }

    return _mediaPlaceholder(Icons.attach_file, att.fileName ?? 'Vedlegg');
  }

  Widget _mediaPlaceholder(IconData icon, String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Svar-stripe over skrivefeltet.
class ChatReplyBar extends StatelessWidget {
  const ChatReplyBar({super.key, required this.reply, required this.onClear});

  final ChatMessage reply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(width: 3, height: 36, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Svarer ${reply.senderName ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  Text(
                    reply.body.isNotEmpty
                        ? reply.body
                        : (reply.messageType == ChatMessageType.video ? 'Video' : 'Bilde'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            IconButton(onPressed: onClear, icon: const Icon(Icons.close, size: 20)),
          ],
        ),
      ),
    );
  }
}
