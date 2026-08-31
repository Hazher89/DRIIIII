import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/chat/chat_models.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/chat/chat_feature_gate.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'widgets/chat_create_group_sheet.dart';
import 'chat_room_screen.dart';

/// Hub for MAVI ↔ partner chat med kanaltyper og personvern.
class PartnerChatHubScreen extends StatefulWidget {
  const PartnerChatHubScreen({
    super.key,
    required this.profile,
    this.embedded = false,
  });

  final UserProfile profile;
  final bool embedded;

  @override
  State<PartnerChatHubScreen> createState() => _PartnerChatHubScreenState();
}

class _PartnerChatHubScreenState extends State<PartnerChatHubScreen> with SingleTickerProviderStateMixin {
  List<ChatRoom> _rooms = const [];
  List<ChatRoom> _archived = const [];
  List<ChatPartnerDirectoryEntry> _partners = const [];
  List<ChatMaviDirectoryEntry> _maviUsers = const [];
  bool _loading = true;
  String? _error;
  late TabController _tabs;

  bool get _isPartner => widget.profile.isPartnerPortalUser;
  bool get _isMavi => widget.profile.isMaviEmployee;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.profile.companyId != null && _isMavi) {
        await PartnerChatService.ensureBroadcastRoom(widget.profile.companyId!);
      }
      final rooms = await PartnerChatService.fetchMyRooms(archived: false);
      final archived = await PartnerChatService.fetchMyRooms(archived: true);
      final partners = _isPartner || _isMavi
          ? await PartnerChatService.fetchPartnerDirectory()
          : const <ChatPartnerDirectoryEntry>[];
      final maviUsers = _isMavi && widget.profile.companyId != null
          ? await PartnerChatService.fetchMaviDirectory(widget.profile.companyId!)
          : const <ChatMaviDirectoryEntry>[];
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _archived = archived;
        _partners = partners;
        _maviUsers = maviUsers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openRoom(ChatRoom room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomLiveGate(
          profile: widget.profile,
          child: ChatRoomScreen(
            room: room,
            profile: widget.profile,
          ),
        ),
      ),
    );
    await _load();
  }

  Future<void> _startPartnerPrivate() async {
    if (_partners.isEmpty) return;
    final me = widget.profile.id;
    final others = _partners.where((p) => p.userId != me).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen andre partnere å chatte med ennå.')),
      );
      return;
    }

    final picked = await showModalBottomSheet<ChatPartnerDirectoryEntry>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Velg partner for privat chat',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'MAVI kan ikke lese denne samtalen. Kun dere to.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: others.length,
                itemBuilder: (_, i) {
                  final p = others[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                      child: Text(p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : '?'),
                    ),
                    title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(p.partnerName),
                    onTap: () => Navigator.pop(ctx, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    try {
      final roomId = await PartnerChatService.createPartnerPrivateChat(picked.userId);
      if (!mounted) return;
      await _openRoom(
        ChatRoom(
          id: roomId,
          companyId: widget.profile.companyId ?? '',
          roomType: ChatRoomType.partnerPrivate,
          title: picked.fullName,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke opprette chat: $e')),
      );
    }
  }

  Future<void> _createPartnerGroup() async {
    final result = await showChatCreateGroupSheet(
      context: context,
      headline: 'Ny partner-gruppe',
      privacyHint: 'MAVI kan ikke lese denne gruppen. Kun inviterte partnere.',
      candidates: _partners
          .map((p) => (id: p.userId, title: p.fullName, subtitle: p.partnerName))
          .toList(),
      currentUserId: widget.profile.id,
      minMembers: 1,
    );
    if (result == null) return;
    try {
      final roomId = await PartnerChatService.createPartnerGroupChat(
        memberIds: result.memberIds,
        title: result.title,
      );
      if (!mounted) return;
      await _openRoom(ChatRoom(
        id: roomId,
        companyId: widget.profile.companyId ?? '',
        roomType: ChatRoomType.partnerGroup,
        title: result.title,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke opprette gruppe: $e')),
      );
    }
  }

  Future<void> _createMaviGroup() async {
    final result = await showChatCreateGroupSheet(
      context: context,
      headline: 'Ny MAVI-gruppe',
      privacyHint: 'Kun MAVI-ansatte i gruppen. Partnere ser ikke denne.',
      candidates: _maviUsers
          .map((u) => (id: u.userId, title: u.fullName, subtitle: 'MAVI-ansatt'))
          .toList(),
      currentUserId: widget.profile.id,
      minMembers: 0,
    );
    if (result == null) return;
    try {
      final roomId = await PartnerChatService.createMaviGroupChat(
        memberIds: result.memberIds,
        title: result.title,
      );
      if (!mounted) return;
      await _openRoom(ChatRoom(
        id: roomId,
        companyId: widget.profile.companyId ?? '',
        roomType: ChatRoomType.maviGroup,
        title: result.title,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke opprette gruppe: $e')),
      );
    }
  }

  Future<void> _archiveRoom(ChatRoom room, {required bool archive}) async {
    await PartnerChatService.setArchived(room.id, archive);
    await _load();
  }

  Widget _roomList(List<ChatRoom> rooms, {required bool archived}) {
    if (rooms.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          Center(
            child: Text(
              archived ? 'Ingen arkiverte samtaler' : 'Ingen aktive samtaler',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rooms.length,
      itemBuilder: (_, i) {
        final r = rooms[i];
        return Dismissible(
          key: ValueKey('${r.id}-$archived'),
          direction: archived ? DismissDirection.endToStart : DismissDirection.startToEnd,
          background: Container(
            alignment: archived ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: archived ? DriftProTheme.primaryGreen : Colors.blueGrey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              color: archived ? Colors.white : Colors.blueGrey.shade800,
            ),
          ),
          confirmDismiss: (_) async {
            await _archiveRoom(r, archive: !archived);
            return false;
          },
          child: _RoomTile(room: r, onTap: () => _openRoom(r)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final listBody = _loading
        ? const Center(child: DriftProLoadingIndicator(size: 48))
        : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _PrivacyBanner(isPartner: _isPartner, isMavi: _isMavi),
                  ),
                  if (!_loading && _error == null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_isPartner) ...[
                            ActionChip(
                              avatar: const Icon(Icons.lock_outline, size: 18),
                              label: const Text('Privat 1:1'),
                              onPressed: _startPartnerPrivate,
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.group_add_outlined, size: 18),
                              label: const Text('Ny gruppe'),
                              onPressed: _createPartnerGroup,
                            ),
                          ],
                          if (_isMavi) ...[
                            ActionChip(
                              avatar: const Icon(Icons.groups_outlined, size: 18),
                              label: const Text('MAVI-gruppe'),
                              onPressed: _createMaviGroup,
                            ),
                          ],
                        ],
                      ),
                    ),
                    TabBar(
                      controller: _tabs,
                      tabs: [
                        Tab(text: 'Aktive (${_rooms.length})'),
                        Tab(text: 'Arkiv (${_archived.length})'),
                      ],
                    ),
                  ],
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        RefreshIndicator(onRefresh: _load, child: _roomList(_rooms, archived: false)),
                        RefreshIndicator(onRefresh: _load, child: _roomList(_archived, archived: true)),
                      ],
                    ),
                  ),
                ],
              );

    if (widget.embedded) return listBody;

    return Scaffold(
      backgroundColor: drift.surfaceMuted,
      appBar: AppBar(
        title: const Text('Meldinger'),
        actions: [
          IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: listBody,
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.isPartner, required this.isMavi});

  final bool isPartner;
  final bool isMavi;

  @override
  Widget build(BuildContext context) {
    final text = isPartner
        ? 'Du ser meldinger fra MAVI og kan chatte privat med andre partnere. '
          'Partner-til-partner-chatter er skjult for MAVI (GDPR).'
        : isMavi
            ? 'Intern MAVI-chat er kun synlig for ansatte. '
              'Partner-private chatter kan ikke leses av MAVI.'
            : 'Sikker meldingskanal med rollebasert tilgang.';

    return Material(
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 12, height: 1.45)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  child: Icon(icon, color: DriftProTheme.primaryGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap});

  final ChatRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = room.lastMessageAt != null
        ? DateFormat('d.M HH:mm', 'nb').format(room.lastMessageAt!)
        : null;
    final typeColor = switch (room.roomType) {
      ChatRoomType.partnerPrivate => Colors.deepPurple,
      ChatRoomType.partnerGroup => Colors.deepPurple.shade400,
      ChatRoomType.partnerBroadcast => DriftProTheme.primaryGreen,
      ChatRoomType.maviPartnerDirect => Colors.blue.shade700,
      ChatRoomType.maviInternal => Colors.blueGrey.shade700,
      ChatRoomType.maviGroup => Colors.indigo.shade700,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: typeColor.withValues(alpha: 0.12),
                  child: Icon(room.roomType.icon, color: typeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.displayTitle(null),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        room.roomType.subtitleNorwegian,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                      if (room.lastMessagePreview != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          room.lastMessagePreview!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                        ),
                      ],
                    ],
                  ),
                ),
                if (time != null)
                  Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.isPartner});
  final bool isPartner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            isPartner ? 'Ingen samtaler ennå' : 'Ingen chat-rom ennå',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            isPartner
                ? 'Meldinger fra MAVI vises her. Start privat chat med en annen partner.'
                : 'Send melding til partnere eller start intern MAVI-chat.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Prøv igjen')),
          ],
        ),
      ),
    );
  }
}
