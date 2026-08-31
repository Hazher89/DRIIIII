import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/chat/partner_chat_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/chat/chat_models.dart';
import '../../models/user_profile.dart';
import 'widgets/chat_media_send_sheet.dart';
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
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
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
    PartnerChatService.unsubscribe(_channel);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final msgs = await PartnerChatService.fetchMessages(widget.room.id);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    if (msgs.isNotEmpty) {
      await PartnerChatService.markRead(widget.room.id, msgs.last.id);
    }
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
    if (text.isEmpty || _sending) return;
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
    if (_sending) return;
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
    final room = widget.room;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.displayTitle(), overflow: TextOverflow.ellipsis),
            Text(room.roomType.subtitleNorwegian, style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') await _archive();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'archive', child: Text('Arkiver samtale')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (room.roomType.isPartnerOnly)
            _PrivacyStrip(text: room.roomType.subtitleNorwegian),
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
                          );
                        },
                      ),
          ),
          if (_replyTo != null)
            ChatReplyBar(reply: _replyTo!, onClear: () => setState(() => _replyTo = null)),
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
