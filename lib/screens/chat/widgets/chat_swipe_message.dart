import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import 'chat_media_viewer.dart';
import 'chat_ui_helpers.dart';

/// Meldingsboble med swipe-for-svar, avatars og inline media.
class ChatSwipeMessage extends StatefulWidget {
  const ChatSwipeMessage({
    super.key,
    required this.message,
    required this.mine,
    required this.onReply,
    this.showSender = false,
    this.onOpenImage,
    this.onDelete,
    this.onHide,
    this.onModeratorDelete,
    this.onShowRead,
  });

  final ChatMessage message;
  final bool mine;
  final bool showSender;
  final ValueChanged<ChatMessage> onReply;
  final void Function(String url)? onOpenImage;
  final VoidCallback? onDelete;
  final VoidCallback? onHide;
  final VoidCallback? onModeratorDelete;
  final VoidCallback? onShowRead;

  @override
  State<ChatSwipeMessage> createState() => _ChatSwipeMessageState();
}

class _ChatSwipeMessageState extends State<ChatSwipeMessage> with SingleTickerProviderStateMixin {
  double _drag = 0;
  late AnimationController _replyPulse;

  @override
  void initState() {
    super.initState();
    _replyPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _replyPulse.dispose();
    super.dispose();
  }

  void _onReply() {
    HapticFeedback.lightImpact();
    widget.onReply(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final m = widget.message;
    final threshold = mine ? -64.0 : 64.0;
    final showReplyHint = mine ? _drag < -20 : _drag > 20;
    final senderName = m.senderName?.trim().isNotEmpty == true ? m.senderName! : 'Bruker';
    final senderColor = mine ? DriftProTheme.primaryGreen : ChatUiHelpers.senderColor(m.senderId);

    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (mine) {
          setState(() => _drag = (_drag + d.delta.dx).clamp(-88.0, 0.0));
        } else {
          setState(() => _drag = (_drag + d.delta.dx).clamp(0.0, 88.0));
        }
      },
      onHorizontalDragEnd: (_) {
        if ((mine && _drag <= threshold) || (!mine && _drag >= threshold)) {
          _onReply();
        }
        setState(() => _drag = 0);
      },
      onLongPress: () => _showActions(context, m),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          if (showReplyHint)
            Positioned(
              right: mine ? 12 : null,
              left: mine ? null : 12,
              child: FadeTransition(
                opacity: _replyPulse,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.reply_rounded, size: 16, color: DriftProTheme.primaryGreen),
                      const SizedBox(width: 6),
                      Text(
                        'Svar $senderName',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: DriftProTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_drag, 0),
            child: Padding(
              padding: EdgeInsets.only(
                left: mine ? 48 : (widget.showSender ? 0 : 4),
                right: mine ? 4 : 48,
                bottom: 6,
              ),
              child: Row(
                mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!mine && widget.showSender) ...[
                    ChatSenderAvatar(name: m.senderName, userId: m.senderId),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Column(
                      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (widget.showSender)
                          Padding(
                            padding: EdgeInsets.only(left: mine ? 0 : 4, right: mine ? 4 : 0, bottom: 4),
                            child: Text(
                              mine ? 'Du' : senderName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: senderColor,
                              ),
                            ),
                          ),
                        _ChatBubbleBody(
                          message: m,
                          mine: mine,
                          onOpenImage: widget.onOpenImage,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context, ChatMessage m) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                child: Icon(Icons.reply_rounded, color: DriftProTheme.primaryGreen),
              ),
              title: Text('Svar ${m.senderName ?? ''}'),
              subtitle: Text(ChatUiHelpers.replySnippet(m), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(ctx);
                _onReply();
              },
            ),
            if (m.body.isNotEmpty && !m.isDeleted)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Kopier tekst'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.body));
                  Navigator.pop(ctx);
                },
              ),
            if (widget.onShowRead != null)
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Lest av'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onShowRead!();
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Slett melding'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onDelete!();
                },
              ),
            if (widget.onModeratorDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                title: const Text('Slett melding (moderator)'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onModeratorDelete!();
                },
              ),
            if (widget.onHide != null)
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined, color: Colors.orange),
                title: const Text('Skjul melding (moderator)'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onHide!();
                },
              ),
          ],
        ),
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
    final m = message;
    final mediaOnly = m.hasMedia && m.body.trim().isEmpty && !m.isDeleted;
    final bg = mine
        ? DriftProTheme.primaryGreen
        : Colors.white;
    final fg = mine ? Colors.white : const Color(0xFF1A1A1A);
    final time = ChatUiHelpers.formatMessageTime(m.createdAt);
    final border = mine
        ? null
        : Border.all(color: Colors.black.withValues(alpha: 0.06));

    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74),
      decoration: BoxDecoration(
        color: m.isBlocked ? Colors.red.shade50 : (mediaOnly ? Colors.transparent : bg),
        borderRadius: BorderRadius.circular(18),
        border: mediaOnly ? null : border,
        boxShadow: mediaOnly
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: mine ? 0.08 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.replyTo != null) _ReplyPreview(reply: m.replyTo!, mine: mine),
              if (m.hasMedia)
                for (final att in m.attachments)
                  _AttachmentView(
                    att: att,
                    message: m,
                    mine: mine,
                    onOpenImage: onOpenImage,
                  ),
              if (!mediaOnly)
                Padding(
                  padding: EdgeInsets.fromLTRB(14, m.hasMedia ? 8 : 10, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.body.isNotEmpty)
                        Text(
                          m.isDeleted ? '[Slettet]' : m.body,
                          style: TextStyle(color: fg, height: 1.4, fontSize: 15),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(time, style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.65))),
                          if (m.isEdited) ...[
                            const SizedBox(width: 6),
                            Text('redigert', style: TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.55))),
                          ],
                          if (mine) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.done_all_rounded, size: 12, color: fg.withValues(alpha: 0.65)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (mediaOnly)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: const TextStyle(fontSize: 10, color: Colors.white)),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.done_all_rounded, size: 11, color: Colors.white70),
                    ],
                  ],
                ),
              ),
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
    final accent = mine ? Colors.white : ChatUiHelpers.senderColor(reply.senderId);
    final replyName = reply.senderName?.trim().isNotEmpty == true ? reply.senderName! : 'Bruker';
    final hasThumb = reply.attachments.isNotEmpty &&
        PartnerChatService.attachmentIsImage(reply.attachments.first, reply.messageType) &&
        reply.attachments.first.signedUrl != null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (mine ? Colors.white : accent).withValues(alpha: mine ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        children: [
          if (hasThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: reply.attachments.first.signedUrl!,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replyName,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent),
                ),
                Text(
                  ChatUiHelpers.replySnippet(reply),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: mine ? Colors.white.withValues(alpha: 0.85) : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentView extends StatelessWidget {
  const _AttachmentView({
    required this.att,
    required this.message,
    required this.mine,
    this.onOpenImage,
  });

  final ChatAttachment att;
  final ChatMessage message;
  final bool mine;
  final void Function(String url)? onOpenImage;

  @override
  Widget build(BuildContext context) {
    final isImage = PartnerChatService.attachmentIsImage(att, message.messageType);
    final isVideo = PartnerChatService.attachmentIsVideo(att, message.messageType);

    if (isImage) {
      if (att.signedUrl != null) {
        final heroTag = 'chat_img_${message.id}_${att.id}';
        return GestureDetector(
          onTap: () {
            if (onOpenImage != null) {
              onOpenImage!(att.signedUrl!);
            } else {
              ChatMediaViewer.openImage(context, att.signedUrl!, heroTag: heroTag);
            }
          },
          child: Hero(
            tag: heroTag,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, minHeight: 120),
              child: CachedNetworkImage(
                imageUrl: att.signedUrl!,
                width: double.infinity,
                fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 160,
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => _mediaCard(
                icon: Icons.broken_image_outlined,
                label: 'Kunne ikke laste bilde',
                mine: mine,
              ),
            ),
          ),
        ),
      );
      }
      return _mediaCard(icon: Icons.image_outlined, label: 'Laster bilde…', mine: mine);
    }

    if (isVideo) {
      return GestureDetector(
        onTap: att.signedUrl == null
            ? null
            : () => ChatMediaViewer.openVideo(context, att.signedUrl!),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (att.signedUrl != null && isImage)
              CachedNetworkImage(
                imageUrl: att.signedUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            else
              _mediaCard(
                icon: Icons.videocam_rounded,
                label: att.fileName ?? 'Video',
                mine: mine,
                height: 180,
              ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
            ),
          ],
        ),
      );
    }

    return _mediaCard(
      icon: Icons.attach_file_rounded,
      label: att.fileName ?? 'Vedlegg',
      mine: mine,
    );
  }

  Widget _mediaCard({
    required IconData icon,
    required String label,
    required bool mine,
    double height = 88,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: mine ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: mine ? Colors.white : DriftProTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: mine ? Colors.white : Colors.black87,
              ),
            ),
          ),
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
    final name = reply.senderName?.trim().isNotEmpty == true ? reply.senderName! : 'Bruker';
    final color = ChatUiHelpers.senderColor(reply.senderId);
    final hasThumb = reply.attachments.isNotEmpty &&
        PartnerChatService.attachmentIsImage(reply.attachments.first, reply.messageType) &&
        reply.attachments.first.signedUrl != null;

    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            ChatSenderAvatar(name: reply.senderName, userId: reply.senderId, radius: 16),
            const SizedBox(width: 10),
            Container(width: 3, height: 42, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            if (hasThumb) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: reply.attachments.first.signedUrl!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Svarer $name',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color),
                  ),
                  Text(
                    ChatUiHelpers.replySnippet(reply),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.25),
                  ),
                ],
              ),
            ),
            IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 20)),
          ],
        ),
      ),
    );
  }
}
