import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/chat/chat_presence_service.dart';
import '../../core/services/chat/chat_unread_service.dart';
import '../../core/services/chat/partner_chat_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/permissions/user_access.dart';
import '../../models/chat/chat_models.dart';
import '../../models/user_profile.dart';
import 'widgets/chat_media_send_sheet.dart';
import 'widgets/chat_room_members_sheet.dart';
import 'widgets/chat_swipe_message.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.room,
    required this.profile,
  });

  final ChatRoom room;
  final UserProfile profile;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  List<ChatMessage> _messages = const [];
  ChatMessage? _replyTo;
  late ChatRoom _room;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _pinned = false;
  bool _muted = false;
  RealtimeChannel? _channel;

  bool get _canSend {
    if (_room.roomType == ChatRoomType.partnerBroadcast) {
      return widget.profile.access.canPartnersChatBroadcast;
    }
    return true;
  }

  bool get _canModerate => widget.profile.access.canPartnersChatModerate;
  bool get _isSuperAdmin => widget.profile.role == UserRole.superadmin;
  bool get _canModerateMessages => _canModerate || _isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _pinned = widget.room.isPinned;
    _muted = widget.room.isMuted;
    ChatPresenceService.setOpenRoom(widget.room.id);
    _scroll.addListener(_onScroll);
    _load();
    _channel = PartnerChatService.subscribeRoom(
      roomId: widget.room.id,
      onMessage: (msg) async {
        if (!mounted) return;
        setState(() {
          final existing = _messages.any((m) => m.id == msg.id);
          if (!existing) _messages = [..._messages, msg];
        });
        await PartnerChatService.markRead(widget.room.id, msg.id);
        _scrollToBottom();
      },
    );
  }

  @override
  void dispose() {
    if (ChatPresenceService.openRoomId == widget.room.id) {
      ChatPresenceService.setOpenRoom(null);
    }
    PartnerChatService.unsubscribe(_channel);
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels <= 48) {
      unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final older = await PartnerChatService.fetchMessages(
        widget.room.id,
        before: _messages.first.createdAt,
      );
      if (!mounted) return;
      setState(() {
        if (older.length < 80) _hasMore = false;
        if (older.isNotEmpty) {
          final existing = _messages.map((m) => m.id).toSet();
          _messages = [
            ...older.where((m) => !existing.contains(m.id)),
            ..._messages,
          ];
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final msgs = await PartnerChatService.fetchMessages(widget.room.id);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
      _hasMore = msgs.length >= 80;
    });
    if (msgs.isNotEmpty) {
      await PartnerChatService.markRead(widget.room.id, msgs.last.id);
    }
    unawaited(ChatUnreadService.refresh());
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || !_canSend) return;
    setState(() => _sending = true);
    final replyId = _replyTo?.id;
    _input.clear();
    setState(() => _replyTo = null);
    try {
      await PartnerChatService.sendMessage(
        roomId: widget.room.id,
        body: text,
        replyToId: replyId,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickMedia({required bool video}) async {
    if (_sending || !_canSend) return;
    try {
      XFile? file;
      if (video) {
        file = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 3));
      } else {
        file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      }
      if (file == null || !mounted) return;

      final bytes = await file.readAsBytes();
      final pending = ChatPendingMedia(
        bytes: bytes,
        mimeType: video ? 'video/mp4' : 'image/jpeg',
        fileName: file.name,
        isVideo: video,
      );

      final result = await ChatMediaSendSheet.show(context, pending);
      if (result == null || !result.send || !mounted) return;

      setState(() => _sending = true);
      await PartnerChatService.uploadAndSendMedia(
        roomId: widget.room.id,
        media: pending,
        caption: result.caption,
        replyToId: _replyTo?.id,
      );
      setState(() => _replyTo = null);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende media: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _archive() async {
    await PartnerChatService.setArchived(widget.room.id, true);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    await PartnerChatService.setPinned(widget.room.id, next);
    if (mounted) setState(() => _pinned = next);
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await PartnerChatService.setMuted(widget.room.id, next, hours: next ? 24 * 7 : null);
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    try {
      await PartnerChatService.deleteOwnMessage(message.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke slette: $e')));
      }
    }
  }

  Future<void> _moderatorDeleteMessage(ChatMessage message) async {
    try {
      await PartnerChatService.moderatorDeleteMessage(message.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke slette: $e')),
        );
      }
    }
  }

  Future<void> _hideMessage(ChatMessage message) async {
    try {
      await PartnerChatService.hideMessage(message.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke skjule: $e')));
      }
    }
  }

  Future<void> _showReadReceipts(ChatMessage message) async {
    final receipts = await PartnerChatService.fetchReadReceipts(widget.room.id, message.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Lest av', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            if (receipts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ikke lest av andre ennå.', textAlign: TextAlign.center),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: receipts.length,
                  itemBuilder: (_, i) {
                    final r = receipts[i];
                    return ListTile(
                      leading: const Icon(Icons.done_all, color: Colors.blue),
                      title: Text(r.fullName),
                      subtitle: Text(
                        '${r.readAt.hour.toString().padLeft(2, '0')}:${r.readAt.minute.toString().padLeft(2, '0')}',
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openImage(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.profile.id;
    final room = _room;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_pinned) ...[
                  const Icon(Icons.push_pin, size: 14),
                  const SizedBox(width: 4),
                ],
                if (_muted) ...[
                  Icon(Icons.notifications_off_outlined, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(room.displayTitle(), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Text(room.roomType.subtitleNorwegian, style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Medlemmer',
            icon: const Icon(Icons.people_outline),
            onPressed: () => showChatRoomMembersSheet(
              context: context,
              room: room,
              profile: widget.profile,
              onRoomDeleted: () => Navigator.pop(context),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'archive':
                  await _archive();
                case 'pin':
                  await _togglePin();
                case 'mute':
                  await _toggleMute();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'pin', child: Text(_pinned ? 'Løsne samtale' : 'Fest samtale')),
              PopupMenuItem(value: 'mute', child: Text(_muted ? 'Slå på varsler' : 'Demp varsler')),
              const PopupMenuItem(value: 'archive', child: Text('Arkiver samtale')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (room.roomType.isPartnerOnly)
            _PrivacyStrip(text: room.roomType.subtitleNorwegian),
          if (room.roomType == ChatRoomType.partnerBroadcast && !_canSend)
            _PrivacyStrip(
              text: 'Kun lesing — du har ikke rettighet til å sende til alle partnere.',
            ),
          if (_loadingMore)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Ingen meldinger ennå.\nSwipe på en melding for å svare.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          return ChatSwipeMessage(
                            message: m,
                            mine: m.senderId == me,
                            onReply: (ChatMessage msg) => setState(() => _replyTo = msg),
                            onOpenImage: _openImage,
                            onDelete: m.senderId == me && !m.isDeleted ? () => _deleteMessage(m) : null,
                            onHide: _canModerate && !m.isDeleted ? () => _hideMessage(m) : null,
                            onModeratorDelete: _canModerateMessages && !m.isDeleted
                                ? () => _moderatorDeleteMessage(m)
                                : null,
                            onShowRead: m.senderId == me ? () => _showReadReceipts(m) : null,
                          );
                        },
                      ),
          ),
          if (_replyTo != null)
            ChatReplyBar(reply: _replyTo!, onClear: () => setState(() => _replyTo = null)),
          if (_canSend)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Bilde',
                      onPressed: _sending ? null : () => _pickMedia(video: false),
                      icon: const Icon(Icons.photo_outlined),
                    ),
                    IconButton(
                      tooltip: 'Video',
                      onPressed: _sending ? null : () => _pickMedia(video: true),
                      icon: const Icon(Icons.videocam_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: 'Skriv melding… (swipe for svar)',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _sending ? null : _sendText,
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.primaryGreen,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.deepPurple.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.lock, size: 16, color: Colors.deepPurple.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade900)),
            ),
          ],
        ),
      ),
    );
  }
}
