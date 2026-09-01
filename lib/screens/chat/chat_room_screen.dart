import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/chat/chat_advanced_service.dart';
import '../../core/services/chat/chat_typing_service.dart';
import '../../core/services/chat/chat_presence_service.dart';
import '../../core/services/storage/company_file_storage.dart';
import '../../core/services/chat/chat_unread_service.dart';
import '../../core/services/chat/partner_chat_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/permissions/user_access.dart';
import '../../models/chat/chat_models.dart';
import '../../models/user_profile.dart';
import 'widgets/chat_media_gallery_sheet.dart';
import 'widgets/chat_media_viewer.dart';
import 'widgets/chat_ui_helpers.dart';
import 'widgets/chat_media_send_sheet.dart';
import 'widgets/chat_room_members_sheet.dart';
import 'widgets/chat_compose_sheets.dart';
import 'widgets/chat_room_banners.dart';
import 'widgets/chat_swipe_message.dart';
import 'widgets/chat_theme.dart';
import 'chat_stats_screen.dart';

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
  bool _searchOpen = false;
  bool _showJumpLatest = false;
  String _searchQuery = '';
  Map<String, String> _typingUsers = {};
  final _searchCtrl = TextEditingController();
  RealtimeChannel? _channel;
  RealtimeChannel? _reactionsChannel;
  ChatTypingService? _typing;
  StreamSubscription<Map<String, String>>? _typingSub;
  Timer? _heartbeatTimer;
  int? _expiresHours;
  bool _showTranslation = false;
  String? _translatedBody;
  ChatMessage? _pinnedMessage;
  String? _rulesText;
  bool _rulesDismissed = false;
  List<ChatOnlineUser> _onlineUsers = const [];
  String? _activeThreadId;
  List<ChatMentionCandidate> _mentionCandidates = const [];
  bool _dragOver = false;

  bool get _canSend {
    if (_room.roomType == ChatRoomType.partnerBroadcast) {
      return widget.profile.access.canPartnersChatBroadcast;
    }
    return true;
  }

  bool get _canModerate => widget.profile.access.canPartnersChatModerate;
  bool get _isSuperAdmin => widget.profile.role == UserRole.superadmin;
  bool get _canModerateMessages => _canModerate || _isSuperAdmin;
  bool get _showSenderNames => _room.roomType.isGroup;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _pinned = widget.room.isPinned;
    _muted = widget.room.isMuted;
    ChatPresenceService.setOpenRoom(widget.room.id);
    _scroll.addListener(_onScroll);
    _typing = ChatTypingService(
      roomId: widget.room.id,
      userId: widget.profile.id,
      userName: widget.profile.fullName.isNotEmpty ? widget.profile.fullName : 'Bruker',
    )..start();
    _typingSub = _typing!.others.listen((map) {
      if (!mounted) return;
      setState(() => _typingUsers = map);
    });
    _input.addListener(() => _typing?.onUserTyping());
    _channel = PartnerChatService.subscribeRoom(
      roomId: widget.room.id,
      onMessage: (msg) async {
        if (!mounted) return;
        ChatMessage incoming = msg;
        if (incoming.replyToId != null) {
          final parent = _messages.cast<ChatMessage?>().firstWhere(
                (m) => m?.id == incoming.replyToId,
                orElse: () => null,
              );
          if (parent != null) incoming = incoming.copyWith(replyTo: parent);
        }
        setState(() {
          final existing = _messages.any((m) => m.id == incoming.id);
          if (!existing) _messages = [..._messages, incoming];
        });
        await PartnerChatService.markRead(widget.room.id, incoming.id);
        _scrollToBottom();
      },
    );
    _reactionsChannel = Supabase.instance.client
        .channel('chat_reactions_${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_message_reactions',
          callback: (_) => unawaited(_load(silent: true)),
        )
        ..subscribe();
    _load();
    unawaited(ChatAdvancedService.processScheduled());
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(ChatAdvancedService.heartbeat(roomId: widget.room.id));
    });
    unawaited(_loadRoomMeta());
    unawaited(_loadOnline());
    unawaited(_loadMentionCandidates());
  }

  Future<void> _loadMentionCandidates() async {
    final members = await PartnerChatService.fetchRoomMembers(widget.room.id);
    if (!mounted) return;
    setState(() {
      _mentionCandidates = members
          .where((m) => m.memberRole != 'pending')
          .map((m) => ChatMentionCandidate(userId: m.userId, label: m.fullName))
          .toList();
    });
  }

  Future<void> _loadRoomMeta() async {
    final meta = await PartnerChatService.fetchRoomMeta(widget.room.id);
    if (!mounted || meta == null) return;
    final pinId = meta['pinned_message_id'] as String?;
    final pinned = await PartnerChatService.fetchPinnedMessage(pinId);
    setState(() {
      _rulesText = (meta['rules_text'] as String?)?.trim();
      _pinnedMessage = pinned;
    });
  }

  Future<void> _loadOnline() async {
    final users = await ChatAdvancedService.fetchOnlineUsers(widget.room.id);
    if (mounted) setState(() => _onlineUsers = users);
  }

  @override
  void dispose() {
    if (ChatPresenceService.openRoomId == widget.room.id) {
      ChatPresenceService.setOpenRoom(null);
    }
    unawaited(_typingSub?.cancel() ?? Future.value());
    _heartbeatTimer?.cancel();
    _typing?.dispose();
    PartnerChatService.unsubscribe(_channel);
    if (_reactionsChannel != null) {
      Supabase.instance.client.removeChannel(_reactionsChannel!);
    }
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients) {
      final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;
      if (atBottom != !_showJumpLatest) setState(() => _showJumpLatest = !atBottom);
    }
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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final msgs = await PartnerChatService.fetchMessages(widget.room.id);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
      _hasMore = msgs.length >= 80;
    });
    if (msgs.isNotEmpty) {
      await PartnerChatService.markRead(widget.room.id, msgs.last.id);
      final me = widget.profile.id;
      for (final m in msgs) {
        if (m.senderId != me && !m.isDeleted) {
          unawaited(ChatAdvancedService.markDelivered(m.id));
        }
      }
    }
    unawaited(ChatUnreadService.refresh());
    if (!silent) _scrollToBottom();
  }

  List<ChatMessage> get _visibleMessages {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _messages;
    return _messages.where((m) {
      final body = m.body.toLowerCase();
      final name = (m.senderName ?? '').toLowerCase();
      return body.contains(q) || name.contains(q);
    }).toList();
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    try {
      await PartnerChatService.toggleReaction(message.id, emoji);
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke reagere: $e')));
      }
    }
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
    final mentions = ChatMentionParser.extractMentionIds(text, _mentionCandidates);
    _input.clear();
    setState(() => _replyTo = null);
    try {
      await PartnerChatService.sendMessage(
        roomId: widget.room.id,
        body: text,
        replyToId: replyId,
        threadRootId: _activeThreadId,
        mentionIds: mentions.isEmpty ? null : mentions,
        expiresHours: _expiresHours,
        translatedBody: _translatedBody,
      );
      setState(() {
        _expiresHours = null;
        _translatedBody = null;
      });
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

  Future<void> _sendDroppedFiles(List<XFile> files) async {
    if (_sending || !_canSend || files.isEmpty) return;
    for (final file in files) {
      if (!mounted) return;
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final isVideo = name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.webm');
      final isImage = !isVideo &&
          (name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.gif') ||
              name.endsWith('.webp'));
      if (!isImage && !isVideo) continue;

      final pending = ChatPendingMedia(
        bytes: bytes,
        mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
        fileName: file.name,
        isVideo: isVideo,
      );
      final result = await ChatMediaSendSheet.show(context, pending);
      if (result == null || !result.send || !mounted) continue;

      setState(() => _sending = true);
      try {
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
            SnackBar(content: Text('Kunne ikke sende: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
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

  Future<void> _pickDocument() async {
    if (_sending || !_canSend) return;
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.first;
    if (f == null || f.bytes == null) return;
    setState(() => _sending = true);
    try {
      final path = 'chat/${widget.room.id}/${widget.profile.id}/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
      final stored = await CompanyFileStorage.upload(
        supabaseBucket: 'chat-media',
        storagePath: path,
        bytes: f.bytes!,
        category: 'chat',
        fileName: f.name,
      );
      await PartnerChatService.sendMessage(
        roomId: widget.room.id,
        body: f.name,
        messageType: ChatMessageType.document,
        attachment: {
          'storage_path': CompanyFileStorage.toStorageReference(stored),
          'mime_type': f.extension != null ? 'application/${f.extension}' : 'application/octet-stream',
          'file_name': f.name,
          'byte_size': f.size,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dokument: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendLocation() async {
    if (_sending || !_canSend) return;
    setState(() => _sending = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition();
      final label = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      await PartnerChatService.sendMessage(
        roomId: widget.room.id,
        body: label,
        messageType: ChatMessageType.location,
        attachment: {
          'storage_path': 'geo://${pos.latitude},${pos.longitude}',
          'mime_type': 'application/geo',
          'file_name': 'Posisjon',
        },
      );
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Posisjon: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _scheduleCurrent() async {
    final when = await ChatScheduleSheet.pick(context, initialBody: _input.text);
    if (when == null) return;
    try {
      await ChatAdvancedService.scheduleMessage(
        roomId: widget.room.id,
        body: _input.text.trim().isEmpty ? '(planlagt media)' : _input.text.trim(),
        scheduledFor: when,
        expiresHours: _expiresHours,
        translatedBody: _translatedBody,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Melding planlagt')));
        _input.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _useTemplate() async {
    final t = await ChatTemplatesSheet.pick(context);
    if (t != null) _input.text = t.body;
  }

  Future<void> _pickSelfDestruct() async {
    final h = await ChatSelfDestructPicker.pick(context);
    setState(() => _expiresHours = h);
  }

  Future<void> _pinMessage(ChatMessage m) async {
    await ChatAdvancedService.pinMessage(widget.room.id, m.id);
    await _loadRoomMeta();
  }

  Future<void> _reportMessage(ChatMessage m) async {
    final reason = await ChatReportSheet.show(context);
    if (reason == null) return;
    await ChatAdvancedService.reportMessage(m.id, reason: reason.isEmpty ? null : reason);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rapport sendt')));
  }

  void _openThread(ChatMessage m) {
    setState(() => _activeThreadId = m.id);
  }

  ChatMessage? get _threadRoot {
    if (_activeThreadId == null) return null;
    for (final m in _messages) {
      if (m.id == _activeThreadId) return m;
    }
    return null;
  }

  Future<void> _createSubgroup() async {
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Ny undergruppe'),
          content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Navn')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Opprett')),
          ],
        );
      },
    );
    if (title == null || title.isEmpty) return;
    await ChatAdvancedService.createSubgroup(parentRoomId: widget.room.id, title: title);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Undergruppe opprettet')));
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
    ChatMediaViewer.openImage(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.profile.id;
    final room = _room;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _sendText(),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => _sendText(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
            tooltip: ChatTheme.dark ? 'Lys modus' : 'Mørk modus',
            icon: Icon(ChatTheme.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => setState(() => ChatTheme.dark = !ChatTheme.dark),
          ),
          if (_canModerateMessages)
            IconButton(
              tooltip: 'Statistikk',
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ChatStatsScreen()),
              ),
            ),
          IconButton(
            tooltip: 'Søk i samtale',
            icon: Icon(_searchOpen ? Icons.close : Icons.search_rounded),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchQuery = '';
                _searchCtrl.clear();
              }
            }),
          ),
          IconButton(
            tooltip: 'Media',
            icon: const Icon(Icons.perm_media_outlined),
            onPressed: () => ChatMediaGallerySheet.show(context, _messages),
          ),
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
                case 'schedule':
                  await _scheduleCurrent();
                case 'template':
                  await _useTemplate();
                case 'selfdestruct':
                  await _pickSelfDestruct();
                case 'subgroup':
                  await _createSubgroup();
                case 'translation':
                  final t = await showDialog<String>(
                    context: context,
                    builder: (ctx) {
                      final c = TextEditingController(text: _translatedBody);
                      return AlertDialog(
                        title: const Text('Oversettelse (valgfritt)'),
                        content: TextField(controller: c, maxLines: 3),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Lagre')),
                        ],
                      );
                    },
                  );
                  if (t != null) setState(() => _translatedBody = t.isEmpty ? null : t);
                case 'toggle_translation':
                  setState(() => _showTranslation = !_showTranslation);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'pin', child: Text(_pinned ? 'Løsne samtale' : 'Fest samtale')),
              PopupMenuItem(value: 'mute', child: Text(_muted ? 'Slå på varsler' : 'Demp varsler')),
              const PopupMenuItem(value: 'schedule', child: Text('Planlegg melding')),
              const PopupMenuItem(value: 'template', child: Text('Hurtigmal')),
              const PopupMenuItem(value: 'selfdestruct', child: Text('Selvdestruerende melding')),
              const PopupMenuItem(value: 'translation', child: Text('Legg til oversettelse')),
              PopupMenuItem(value: 'toggle_translation', child: Text(_showTranslation ? 'Vis original' : 'Vis oversettelse')),
              if (room.roomType.isGroup)
                const PopupMenuItem(value: 'subgroup', child: Text('Opprett undergruppe')),
              const PopupMenuItem(value: 'archive', child: Text('Arkiver samtale')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: ChatTheme.backgroundGradient(context)),
        child: Column(
        children: [
          if (_pinnedMessage != null)
            ChatPinnedMessageBar(
              message: _pinnedMessage!,
              onTap: _scrollToBottom,
              onUnpin: () async {
                await ChatAdvancedService.unpinMessage(widget.room.id);
                setState(() => _pinnedMessage = null);
              },
            ),
          if (_rulesText != null && _rulesText!.isNotEmpty && !_rulesDismissed)
            ChatRulesBanner(rules: _rulesText!, onDismiss: () => setState(() => _rulesDismissed = true)),
          ChatOnlineStrip(users: _onlineUsers),
          if (room.roomType.isPartnerOnly)
            _PrivacyStrip(text: room.roomType.subtitleNorwegian),
          if (room.roomType == ChatRoomType.partnerBroadcast && !_canSend)
            _PrivacyStrip(
              text: 'Kun lesing — du har ikke rettighet til å sende til alle partnere.',
            ),
          if (_activeThreadId != null && _threadRoot != null)
            Material(
              color: Colors.blue.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tråd: ${ChatUiHelpers.replySnippet(_threadRoot!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _activeThreadId = null),
                      child: const Text('Lukk'),
                    ),
                  ],
                ),
              ),
            ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Søk i meldinger eller avsendere…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          if (_typingUsers.isNotEmpty)
            _TypingStrip(label: ChatTypingService.typingLabel(_typingUsers)),
          if (_loadingMore)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _dragOver = true),
              onDragExited: (_) => setState(() => _dragOver = false),
              onDragDone: (detail) async {
                setState(() => _dragOver = false);
                final files = detail.files.map((f) => XFile(f.path)).toList();
                await _sendDroppedFiles(files);
              },
              child: Stack(
                children: [
                  if (_dragOver)
                    Positioned.fill(
                      child: ColoredBox(
                        color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                        child: const Center(
                          child: Text('Slipp filer for å sende', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  _loading
                ? const Center(child: CircularProgressIndicator())
                : _visibleMessages.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'Ingen meldinger ennå.\nSwipe på en melding for å svare.'
                              : 'Ingen treff for «$_searchQuery»',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            itemCount: _visibleMessages.length,
                            itemBuilder: (_, i) {
                              final m = _visibleMessages[i];
                              final prev = i > 0 ? _visibleMessages[i - 1] : null;
                              final showDate = ChatUiHelpers.shouldShowDateHeader(m.createdAt, prev?.createdAt);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDate)
                                    ChatDateHeader(label: ChatUiHelpers.formatDayLabel(m.createdAt)),
                                  ChatSwipeMessage(
                                    message: m,
                                    mine: m.senderId == me,
                                    showSender: _showSenderNames,
                                    onReply: (ChatMessage msg) => setState(() => _replyTo = msg),
                                    onOpenImage: _openImage,
                                    onReact: (e) => _toggleReaction(m, e),
                                    onDelete: m.senderId == me && !m.isDeleted ? () => _deleteMessage(m) : null,
                                    onHide: _canModerate && !m.isDeleted ? () => _hideMessage(m) : null,
                                    onModeratorDelete: _canModerateMessages && !m.isDeleted
                                        ? () => _moderatorDeleteMessage(m)
                                        : null,
                                    onShowRead: m.senderId == me ? () => _showReadReceipts(m) : null,
                                    onPin: _canModerateMessages ? () => _pinMessage(m) : null,
                                    onReport: !m.isDeleted ? () => _reportMessage(m) : null,
                                    onThread: _room.roomType.isGroup ? () => _openThread(m) : null,
                                    showTranslation: _showTranslation,
                                  ),
                                ],
                              );
                            },
                          ),
                          if (_showJumpLatest && !_searchOpen)
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: FloatingActionButton.small(
                                heroTag: 'jump_latest',
                                backgroundColor: DriftProTheme.primaryGreen,
                                onPressed: _scrollToBottom,
                                child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                ],
              ),
            ),
          ),
          if (_replyTo != null)
            ChatReplyBar(reply: _replyTo!, onClear: () => setState(() => _replyTo = null)),
          if (_canSend)
            SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _InputIconButton(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Dokument',
                      onTap: _sending ? null : _pickDocument,
                    ),
                    _InputIconButton(
                      icon: Icons.location_on_outlined,
                      tooltip: 'Posisjon',
                      onTap: _sending ? null : _sendLocation,
                    ),
                    _InputIconButton(
                      icon: Icons.photo_library_rounded,
                      tooltip: 'Bilde',
                      onTap: _sending ? null : () => _pickMedia(video: false),
                    ),
                    _InputIconButton(
                      icon: Icons.videocam_rounded,
                      tooltip: 'Video',
                      onTap: _sending ? null : () => _pickMedia(video: true),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: _replyTo != null
                              ? 'Skriv svar til ${_replyTo!.senderName ?? 'bruker'}…'
                              : 'Skriv melding…',
                          filled: true,
                          fillColor: const Color(0xFFF3F5F4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: DriftProTheme.primaryGreen.withValues(alpha: 0.5)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : _sendText,
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.primaryGreen,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                        elevation: 2,
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
      ),
        ),
      ),
    );
  }
}

class _TypingStrip extends StatelessWidget {
  const _TypingStrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DriftProTheme.primaryGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputIconButton extends StatelessWidget {
  const _InputIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
      ),
      icon: Icon(icon, color: DriftProTheme.primaryGreen, size: 22),
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
