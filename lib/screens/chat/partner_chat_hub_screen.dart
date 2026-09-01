import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/chat/chat_pending_navigation.dart';
import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/services/chat/chat_unread_service.dart';
import '../../../core/services/chat/chat_realtime_notification_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/chat/chat_models.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/chat/chat_feature_gate.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'widgets/chat_create_group_sheet.dart';
import 'widgets/chat_superadmin_panel.dart';
import 'widgets/chat_room_members_sheet.dart';
import 'chat_room_screen.dart';
import 'chat_moderation_screen.dart';

/// Hub for MAVI ↔ partner chat med kanaltyper og personvern.
class PartnerChatHubScreen extends StatefulWidget {
  const PartnerChatHubScreen({
    super.key,
    required this.profile,
    this.embedded = false,
    this.initialRoomId,
  });

  final UserProfile profile;
  final bool embedded;
  final String? initialRoomId;

  @override
  State<PartnerChatHubScreen> createState() => _PartnerChatHubScreenState();
}

class _PartnerChatHubScreenState extends State<PartnerChatHubScreen> with SingleTickerProviderStateMixin {
  List<ChatRoom> _rooms = const [];
  List<ChatRoom> _archived = const [];
  List<ChatPartnerDirectoryEntry> _partners = const [];
  List<ChatMaviDirectoryEntry> _maviUsers = const [];
  ChatSuperadminDirectory? _superadminDir;
  List<ChatBlockedUser> _blocked = const [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  bool _webNotifOn = false;
  late TabController _tabs;
  RealtimeChannel? _hubChannel;
  Timer? _hubRefreshDebounce;

  bool get _isPartner => widget.profile.isPartnerPortalUser;
  bool get _isMavi => widget.profile.isMaviEmployee;
  bool get _isSuperAdmin => widget.profile.role == UserRole.superadmin;
  bool get _canModerate => widget.profile.access.canPartnersChatModerate;
  bool get _canBroadcast => widget.profile.access.canPartnersChatBroadcast;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    unawaited(ChatUnreadService.refresh());
    unawaited(ChatRealtimeNotificationService.start());
    _startHubRealtime();
    if (kIsWeb) _refreshWebNotifState();
    _load();
  }

  Future<void> _refreshWebNotifState() async {
    final on = await ChatRealtimeNotificationService.webNotificationsEnabled();
    if (mounted) setState(() => _webNotifOn = on);
  }

  Future<void> _enableWebNotifications() async {
    final ok = await ChatRealtimeNotificationService.enableWebNotifications();
    if (!mounted) return;
    setState(() => _webNotifOn = ok);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Nettleservarsler er på — du får varsel ved nye meldinger.' : 'Tillatelse ble ikke gitt.',
        ),
      ),
    );
  }

  List<ChatRoom> _filterRooms(List<ChatRoom> rooms) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return rooms;
    return rooms.where((r) {
      final title = r.displayTitle().toLowerCase();
      final preview = (r.lastMessagePreview ?? '').toLowerCase();
      final type = r.roomType.labelNorwegian.toLowerCase();
      return title.contains(q) || preview.contains(q) || type.contains(q);
    }).toList();
  }

  void _startHubRealtime() {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    _hubChannel?.unsubscribe();
    _hubChannel = SupabaseService.client
        .channel('chat_hub_list_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _scheduleHubRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_rooms',
          callback: (_) => _scheduleHubRefresh(),
        )
        ..subscribe();
  }

  void _scheduleHubRefresh() {
    _hubRefreshDebounce?.cancel();
    _hubRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(ChatUnreadService.refresh());
      unawaited(_load(silent: true));
    });
  }

  @override
  void dispose() {
    _hubRefreshDebounce?.cancel();
    if (_hubChannel != null) {
      SupabaseService.client.removeChannel(_hubChannel!);
      _hubChannel = null;
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (widget.profile.companyId != null && _isMavi) {
        await PartnerChatService.ensureBroadcastRoom(widget.profile.companyId!);
      }
      final rooms = await PartnerChatService.fetchMyRooms(archived: false);
      final archived = await PartnerChatService.fetchMyRooms(archived: true);

      List<ChatPartnerDirectoryEntry> partners = const [];
      List<ChatMaviDirectoryEntry> maviUsers = const [];
      ChatSuperadminDirectory? superadminDir;

      if (_isSuperAdmin) {
        superadminDir = await PartnerChatService.fetchSuperadminDirectory();
        partners = superadminDir.partners;
        maviUsers = superadminDir.mavi;
      } else if (_isPartner) {
        partners = await PartnerChatService.fetchPartnerDirectory();
      } else if (_isMavi) {
        maviUsers = widget.profile.companyId != null
            ? await PartnerChatService.fetchMaviDirectory(widget.profile.companyId!)
            : const [];
      }

      if (_isPartner) {
        _blocked = await PartnerChatService.fetchPartnerBlockedUsers();
      }

      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _archived = archived;
        _partners = partners;
        _maviUsers = maviUsers;
        _superadminDir = superadminDir;
        _loading = false;
      });
      await _openPendingRoom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openPendingRoom() async {
    final pending = widget.initialRoomId ?? ChatPendingNavigation.takeRoomId();
    if (pending == null || !mounted) return;
    final room = await PartnerChatService.fetchRoomById(pending);
    if (room == null || !mounted) return;
    await _openRoom(room);
  }

  Future<void> _openBroadcast() async {
    final companyId = widget.profile.companyId;
    if (companyId == null) return;
    try {
      final roomId = await PartnerChatService.ensureBroadcastRoom(companyId);
      if (!mounted) return;
      await _openRoom(ChatRoom(
        id: roomId,
        companyId: companyId,
        roomType: ChatRoomType.partnerBroadcast,
        title: 'Meldinger fra MAVI',
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke åpne broadcast: $e')),
      );
    }
  }

  Future<void> _showBlockedUsers() async {
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
              child: Text('Blokkerte brukere', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            if (_blocked.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ingen blokkerte brukere.', textAlign: TextAlign.center),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _blocked.length,
                  itemBuilder: (_, i) {
                    final b = _blocked[i];
                    return ListTile(
                      title: Text(b.fullName),
                      subtitle: Text(b.reason ?? 'Blokkert'),
                      trailing: TextButton(
                        onPressed: () async {
                          await PartnerChatService.partnerUnblockUser(b.userId);
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                        },
                        child: const Text('Avblokker'),
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

  Future<void> _openModeration() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatModerationScreen(profile: widget.profile),
      ),
    );
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
                    subtitle: Text('${p.partnerName} · ${p.roleLabel}'),
                    trailing: IconButton(
                      tooltip: 'Blokker',
                      icon: const Icon(Icons.block_outlined, size: 20),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            title: const Text('Blokker bruker?'),
                            content: Text(
                              '${p.fullName} kan ikke lenger kontakte deg på chat. '
                              'Du kan chatte med andre bil-eiere og ansatte.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Avbryt')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Blokker')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await PartnerChatService.partnerBlockUser(p.userId);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                    ),
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
      minMembers: 2,
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
          child: _RoomTile(
            room: r,
            onTap: () => _openRoom(r),
            onLongPress: _isSuperAdmin
                ? () => showChatRoomMembersSheet(
                      context: context,
                      room: r,
                      profile: widget.profile,
                      onChanged: _load,
                      onRoomDeleted: _load,
                    )
                : null,
          ),
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
                    child: _PrivacyBanner(
                      isPartner: _isPartner,
                      isMavi: _isMavi,
                      isSuperAdmin: _isSuperAdmin,
                    ),
                  ),
                  if (kIsWeb && !_webNotifOn)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Material(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          leading: Icon(Icons.notifications_active_outlined, color: Colors.blue.shade700),
                          title: const Text('Slå på nettleservarsler', style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: const Text(
                            'Få varsel på web når nye meldinger kommer — også når fanen er i bakgrunnen.',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: FilledButton(
                            onPressed: _enableWebNotifications,
                            child: const Text('Aktiver'),
                          ),
                        ),
                      ),
                    ),
                  if (_isSuperAdmin && _superadminDir != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: ChatSuperadminPanel(
                        directory: _superadminDir!,
                        existingRooms: _rooms,
                        onRoomCreated: (roomId, type, title) async {
                          await _openRoom(ChatRoom(
                            id: roomId,
                            companyId: widget.profile.companyId ?? '',
                            roomType: type,
                            title: title,
                          ));
                          await _load();
                        },
                      ),
                    ),
                  if (!_loading && _error == null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Søk i samtaler…',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
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
                            ActionChip(
                              avatar: const Icon(Icons.block_outlined, size: 18),
                              label: Text('Blokkerte (${_blocked.length})'),
                              onPressed: _showBlockedUsers,
                            ),
                          ],
                          if (_isMavi && !_isSuperAdmin) ...[
                            ActionChip(
                              avatar: const Icon(Icons.groups_outlined, size: 18),
                              label: const Text('MAVI-gruppe'),
                              onPressed: _createMaviGroup,
                            ),
                          ],
                          if (_isMavi && _canBroadcast) ...[
                            ActionChip(
                              avatar: const Icon(Icons.campaign_outlined, size: 18),
                              label: const Text('Send til alle partnere'),
                              onPressed: _openBroadcast,
                            ),
                          ],
                        ],
                      ),
                    ),
                    TabBar(
                      controller: _tabs,
                      tabs: [
                        Tab(text: 'Aktive (${_filterRooms(_rooms).length})'),
                        Tab(text: 'Arkiv (${_filterRooms(_archived).length})'),
                      ],
                    ),
                  ],
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _roomList(_filterRooms(_rooms), archived: false),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _roomList(_filterRooms(_archived), archived: true),
                        ),
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
          if (_canModerate)
            IconButton(
              tooltip: 'Moderering',
              onPressed: _openModeration,
              icon: const Icon(Icons.shield_outlined),
            ),
          IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: listBody,
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({
    required this.isPartner,
    required this.isMavi,
    this.isSuperAdmin = false,
  });

  final bool isPartner;
  final bool isMavi;
  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    final text = isSuperAdmin
        ? 'Som superadmin ser du MAVI, partnere og bedrifter — kun du kan koble dem sammen. '
          'Vanlige MAVI-ansatte ser aldri partnerlister.'
        : isPartner
            ? 'Du ser meldinger fra MAVI og kan chatte med andre bil-eiere og ansatte. '
              'Partner-til-partner-chatter er skjult for MAVI (GDPR). Du kan blokkere andre partnere.'
            : isMavi
                ? 'Du ser kun andre MAVI-ansatte. Partnerbedrifter og private partner-chatter '
                  'er skjult. Kun superadmin kan koble MAVI og partnere.'
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
  const _RoomTile({
    required this.room,
    required this.onTap,
    this.onLongPress,
  });

  final ChatRoom room;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
          onLongPress: onLongPress,
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
                      Row(
                        children: [
                          if (room.isPinned) ...[
                            Icon(Icons.push_pin, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                          ],
                          if (room.isMuted) ...[
                            Icon(Icons.notifications_off_outlined, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              room.displayTitle(null),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: room.unreadCount > 0 ? Colors.black : null,
                              ),
                            ),
                          ),
                        ],
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: room.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (time != null)
                      Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if (room.unreadCount > 0) ...[
                      const SizedBox(height: 4),
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: DriftProTheme.primaryGreen,
                        child: Text(
                          room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                          style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ],
                ),
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
