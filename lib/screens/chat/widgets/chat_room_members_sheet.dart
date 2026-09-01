import 'package:flutter/material.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import '../../../models/user_profile.dart';

/// Vis medlemmer i et rom — superadmin kan fjerne enkeltpersoner.
Future<void> showChatRoomMembersSheet({
  required BuildContext context,
  required ChatRoom room,
  required UserProfile profile,
  VoidCallback? onChanged,
  VoidCallback? onRoomDeleted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _MembersSheet(
      room: room,
      profile: profile,
      onChanged: onChanged,
      onRoomDeleted: onRoomDeleted,
    ),
  );
}

class _MembersSheet extends StatefulWidget {
  const _MembersSheet({
    required this.room,
    required this.profile,
    this.onChanged,
    this.onRoomDeleted,
  });

  final ChatRoom room;
  final UserProfile profile;
  final VoidCallback? onChanged;
  final VoidCallback? onRoomDeleted;

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  List<ChatRoomMember> _members = const [];
  bool _loading = true;

  bool get _isSuperAdmin => widget.profile.role == UserRole.superadmin;
  bool get _canDeleteRoom =>
      _isSuperAdmin && widget.room.roomType != ChatRoomType.partnerBroadcast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final members = await PartnerChatService.fetchRoomMembers(widget.room.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste medlemmer: $e')),
      );
    }
  }

  Future<void> _removeMember(ChatRoomMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Fjern fra chat?'),
        content: Text('${member.fullName} fjernes fra «${widget.room.displayTitle()}».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Fjern'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PartnerChatService.superadminRemoveFromRoom(
        roomId: widget.room.id,
        userId: member.userId,
      );
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke fjerne: $e')),
      );
    }
  }

  Future<void> _deleteRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Slett chat permanent?'),
        content: Text(
          '«${widget.room.displayTitle()}» og alle meldinger slettes. '
          'Dette kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Slett chat'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PartnerChatService.superadminDeleteRoom(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onRoomDeleted?.call();
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat slettet')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke slette: $e')),
      );
    }
  }

  Future<void> _leaveRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Forlat chat?'),
        content: const Text('Du vil ikke lenger se denne samtalen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Forlat')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PartnerChatService.leaveRoom(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke forlate: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scroll) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Medlemmer (${_members.length})',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                widget.room.displayTitle(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_members.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    widget.room.roomType == ChatRoomType.partnerBroadcast
                        ? 'Alle partnere i bedriften ser denne kanalen.'
                        : 'Ingen medlemmer funnet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: _members.length,
                  itemBuilder: (_, i) {
                    final m = _members[i];
                    final isMe = m.userId == widget.profile.id;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                        child: Text(m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?'),
                      ),
                      title: Text(
                        isMe ? '${m.fullName} (deg)' : m.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(m.subtitle),
                      trailing: _isSuperAdmin && !isMe
                          ? IconButton(
                              tooltip: 'Fjern fra chat',
                              icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                              onPressed: () => _removeMember(m),
                            )
                          : null,
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isSuperAdmin && widget.room.roomType != ChatRoomType.partnerBroadcast)
                    OutlinedButton.icon(
                      onPressed: _leaveRoom,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Forlat chat'),
                    ),
                  if (_canDeleteRoom) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: _deleteRoom,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Slett chat permanent'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
