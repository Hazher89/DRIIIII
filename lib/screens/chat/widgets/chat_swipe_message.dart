import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import 'chat_media_viewer.dart';
import 'chat_link_text.dart';
import 'chat_location_map_bubble.dart';
import 'chat_ui_helpers.dart';
import 'chat_whatsapp_actions.dart';

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
    this.onReact,
    this.onPin,
    this.onReport,
    this.onThread,
    this.onPrivate,
    this.threadReplyCount = 0,
    this.showTranslation = false,
    this.inThreadView = false,
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
  final void Function(String emoji)? onReact;
  final VoidCallback? onPin;
  final VoidCallback? onReport;
  final VoidCallback? onThread;
  final VoidCallback? onPrivate;
  final int threadReplyCount;
  final bool showTranslation;
  final bool inThreadView;

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
                bottom: m.reactions.isNotEmpty && !m.isDeleted ? 14 : 4,
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
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: m.reactions.isNotEmpty && !m.isDeleted ? 10 : 0,
                              ),
                              child: _ChatBubbleBody(
                                message: widget.showTranslation
                                    ? m.copyWith(showTranslation: true)
                                    : m,
                                mine: mine,
                                onOpenImage: widget.onOpenImage,
                              ),
                            ),
                            if (m.reactions.isNotEmpty && !m.isDeleted)
                              Positioned(
                                // WhatsApp: reaksjon nederst til høyre på boblen.
                                right: 8,
                                bottom: -4,
                                child: _ReactionBar(
                                  reactions: m.reactions,
                                  mine: mine,
                                  onReact: widget.onReact,
                                ),
                              ),
                          ],
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

  Future<void> _showActions(BuildContext context, ChatMessage m) async {
    await showChatWhatsAppActions(
      context: context,
      mine: widget.mine,
      messagePreview: IgnorePointer(
        child: _ChatBubbleBody(
          message: widget.showTranslation ? m.copyWith(showTranslation: true) : m,
          mine: widget.mine,
          onOpenImage: null,
        ),
      ),
      onReact: widget.onReact,
      onReply: _onReply,
      onPrivate: widget.onPrivate,
      onCopy: (m.body.isNotEmpty && !m.isDeleted)
          ? () => Clipboard.setData(ClipboardData(text: m.body))
          : null,
      onPin: widget.onPin,
      onReport: widget.onReport,
      onShowRead: widget.onShowRead,
      onDelete: widget.onDelete,
      onSuperAdminDelete: widget.onModeratorDelete,
      onHide: widget.onHide,
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
    final isLocation = m.messageType == ChatMessageType.location;
    final locationCoords = isLocation
        ? ChatLocationMapBubble.parseCoords(
            body: m.body,
            storagePath: m.attachments.isNotEmpty ? m.attachments.first.storagePath : null,
          )
        : null;
    final mediaOnly = (m.hasMedia || locationCoords != null) &&
        (m.body.trim().isEmpty || isLocation) &&
        !m.isDeleted;
    final bg = mine
        ? DriftProTheme.primaryGreen
        : Colors.white;
    final fg = mine ? Colors.white : const Color(0xFF1A1A1A);
    final time = ChatUiHelpers.formatMessageTime(m.createdAt);
    final border = mine
        ? null
        : Border.all(color: Colors.black.withValues(alpha: 0.06));

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * (locationCoords != null ? 0.82 : 0.74),
      ),
      decoration: BoxDecoration(
        color: m.isBlocked
            ? Colors.red.shade50
            : (mediaOnly && locationCoords != null
                ? (mine ? DriftProTheme.primaryGreen : Colors.white)
                : (mediaOnly ? Colors.transparent : bg)),
        borderRadius: BorderRadius.circular(18),
        border: mediaOnly && locationCoords == null ? null : border,
        boxShadow: mediaOnly && locationCoords == null
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
              if (locationCoords != null && !m.hasMedia)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: ChatLocationMapBubble(
                    latitude: locationCoords.lat,
                    longitude: locationCoords.lng,
                    label: m.body,
                    mine: mine,
                  ),
                ),
              if (m.hasMedia)
                for (final att in m.attachments)
                  _AttachmentView(
                    att: att,
                    message: m,
                    mine: mine,
                    onOpenImage: onOpenImage,
                  ),
              if (!mediaOnly || (isLocation && m.body.trim().isNotEmpty && locationCoords == null))
                Padding(
                  padding: EdgeInsets.fromLTRB(14, m.hasMedia || locationCoords != null ? 8 : 10, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.body.isNotEmpty && !isLocation)
                        m.isDeleted
                            ? Text('[Slettet]', style: TextStyle(color: fg, height: 1.4, fontSize: 15))
                            : ChatLinkText(
                                text: m.displayBody,
                                style: TextStyle(color: fg, height: 1.4, fontSize: 15),
                                linkColor: mine ? Colors.white : DriftProTheme.primaryGreen,
                              ),
                      if (m.isEphemeral)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '⏱ Utløper ${ChatUiHelpers.formatMessageTime(m.expiresAt!)}',
                            style: TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.6)),
                          ),
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
              // Kart uten bilde-overlay: én tid nederst til høyre.
              if (mediaOnly && locationCoords != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(time, style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.65))),
                        if (mine) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.done_all_rounded, size: 12, color: fg.withValues(alpha: 0.65)),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // Bilde/video: kun overlay-tid (ikke ekstra tid under).
          if (mediaOnly && locationCoords == null)
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

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.reactions,
    required this.mine,
    required this.onReact,
  });

  final List<ChatReactionGroup> reactions;
  final bool mine;
  final void Function(String emoji)? onReact;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => showChatReactionDetails(
        context: context,
        reactions: reactions,
        onToggle: onReact,
      ),
      child: Material(
        elevation: 2,
        shadowColor: Colors.black26,
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < reactions.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Text(reactions[i].emoji, style: const TextStyle(fontSize: 14)),
              ],
              if (reactions.any((r) => r.count > 1) || reactions.length > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '${reactions.fold<int>(0, (s, r) => s + r.count)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ],
          ),
        ),
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
    final accent = ChatUiHelpers.senderColor(reply.senderId);
    final barColor = mine ? Colors.white : accent;
    final replyName = reply.senderName?.trim().isNotEmpty == true ? reply.senderName! : 'Bruker';
    final thumb = replyMediaThumb(reply, size: 48);
    final snippet = ChatUiHelpers.replySnippet(reply);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.16)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: barColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            replyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: mine ? Colors.white : accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            snippet,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: mine
                                  ? Colors.white.withValues(alpha: 0.88)
                                  : const Color(0xFF3A3A3A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (thumb != null) ...[
                      const SizedBox(width: 8),
                      thumb,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget? replyMediaThumb(ChatMessage reply, {double size = 48}) {
  final type = reply.messageType;
  if (type == ChatMessageType.location ||
      (reply.attachments.isNotEmpty && reply.attachments.first.mimeType == 'application/geo')) {
    final coords = ChatLocationMapBubble.parseCoords(
      body: reply.body,
      storagePath: reply.attachments.isNotEmpty ? reply.attachments.first.storagePath : null,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coords != null)
              FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(coords.lat, coords.lng),
                  initialZoom: 14,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'no.driftpro.driftpro',
                  ),
                ],
              )
            else
              ColoredBox(color: const Color(0xFFD1D5DB)),
            const Center(
              child: Icon(Icons.location_on_rounded, color: Color(0xFFE11D48), size: 22),
            ),
          ],
        ),
      ),
    );
  }

  if (reply.attachments.isEmpty) return null;
  final att = reply.attachments.first;
  final isImage = PartnerChatService.attachmentIsImage(att, type);
  final isVideo = PartnerChatService.attachmentIsVideo(att, type);

  if (isImage && att.signedUrl != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: att.signedUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }

  if (isVideo) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
            ),
          ],
        ),
      ),
    );
  }

  return null;
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

    if (message.messageType == ChatMessageType.location || att.mimeType == 'application/geo') {
      final coords = ChatLocationMapBubble.parseCoords(
        body: message.body,
        storagePath: att.storagePath,
      );
      if (coords != null) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: SizedBox(
            width: 240,
            child: ChatLocationMapBubble(
              latitude: coords.lat,
              longitude: coords.lng,
              label: message.body,
              mine: mine,
            ),
          ),
        );
      }
      return InkWell(
        onTap: () async {
          final uri = Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(message.body)}');
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: _mediaCard(icon: Icons.location_on_rounded, label: message.body.isNotEmpty ? message.body : 'Posisjon', mine: mine),
      );
    }

    if (message.messageType == ChatMessageType.document || message.messageType == ChatMessageType.voice) {
      return InkWell(
        onTap: att.signedUrl == null ? null : () => launchUrl(Uri.parse(att.signedUrl!), mode: LaunchMode.externalApplication),
        child: _mediaCard(
          icon: message.messageType == ChatMessageType.voice ? Icons.mic_rounded : Icons.insert_drive_file_rounded,
          label: att.fileName ?? message.body,
          mine: mine,
        ),
      );
    }

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
    final thumb = replyMediaThumb(reply, size: 44);

    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Container(width: 4, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            if (thumb != null) ...[
              thumb,
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Svarer $name',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ChatUiHelpers.replySnippet(reply),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.3),
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
