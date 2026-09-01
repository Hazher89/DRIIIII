import 'package:flutter/material.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import 'chat_create_group_sheet.dart';

/// Superadmin: opprett grupper, koble MAVI↔partner, inviter — full kontroll.
class ChatSuperadminPanel extends StatelessWidget {
  const ChatSuperadminPanel({
    super.key,
    required this.directory,
    required this.onRoomCreated,
    this.existingRooms = const [],
  });

  final ChatSuperadminDirectory directory;
  final Future<void> Function(String roomId, ChatRoomType type, String title) onRoomCreated;
  final List<ChatRoom> existingRooms;

  Future<void> _createMaviGroup(BuildContext context) async {
    final result = await showChatCreateGroupSheet(
      context: context,
      headline: 'Ny MAVI-gruppe',
      privacyHint: 'Kun MAVI-ansatte. Partnere ser aldri denne gruppen.',
      candidates: directory.mavi
          .map((u) => (id: u.userId, title: u.fullName, subtitle: 'MAVI-ansatt'))
          .toList(),
      currentUserId: '',
      minMembers: 0,
    );
    if (result == null) return;
    try {
      final roomId = await PartnerChatService.superadminCreateMaviGroup(
        memberIds: result.memberIds,
        title: result.title,
      );
      await onRoomCreated(roomId, ChatRoomType.maviGroup, result.title);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette: $e')),
        );
      }
    }
  }

  Future<void> _createPartnerGroup(BuildContext context) async {
    final result = await showChatCreateGroupSheet(
      context: context,
      headline: 'Ny partner-gruppe',
      privacyHint: 'Kun inviterte partnere/sjåfører/ansatte. MAVI kan ikke lese.',
      candidates: directory.partners
          .map((p) => (
                id: p.userId,
                title: p.fullName,
                subtitle: '${p.partnerName} · ${p.roleLabel}',
              ))
          .toList(),
      currentUserId: '',
      minMembers: 1,
    );
    if (result == null) return;
    try {
      final roomId = await PartnerChatService.superadminCreatePartnerGroup(
        memberIds: result.memberIds,
        title: result.title,
      );
      await onRoomCreated(roomId, ChatRoomType.partnerGroup, result.title);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette: $e')),
        );
      }
    }
  }

  Future<void> _bridgePartner(BuildContext context) async {
    if (directory.companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen partnerbedrifter registrert.')),
      );
      return;
    }

    final picked = await showModalBottomSheet<ChatPartnerCompanyEntry>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Koble MAVI ↔ partnerbedrift',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Kun superadmin kan opprette denne koblingen. '
                'MAVI-ansatte og partner ser hverandre kun i dette rommet.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: directory.companies.length,
                itemBuilder: (_, i) {
                  final c = directory.companies[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.apartment_outlined)),
                    title: Text(c.partnerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(c.ownerName ?? 'Partnerbedrift'),
                    onTap: () => Navigator.pop(ctx, c),
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
      final roomId = await PartnerChatService.createMaviPartnerDirectChat(picked.partnerId);
      await onRoomCreated(
        roomId,
        ChatRoomType.maviPartnerDirect,
        picked.partnerName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke koble: $e')),
        );
      }
    }
  }

  Future<void> _inviteToRoom(BuildContext context) async {
    final groupRooms = existingRooms
        .where((r) => r.roomType == ChatRoomType.maviGroup || r.roomType == ChatRoomType.partnerGroup)
        .toList();
    if (groupRooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen grupper å invitere til ennå.')),
      );
      return;
    }

    final room = await showModalBottomSheet<ChatRoom>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Velg gruppe', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: groupRooms.length,
                itemBuilder: (_, i) {
                  final r = groupRooms[i];
                  return ListTile(
                    leading: Icon(r.roomType.icon),
                    title: Text(r.displayTitle()),
                    subtitle: Text(r.roomType.labelNorwegian),
                    onTap: () => Navigator.pop(ctx, r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (room == null) return;

    final isMaviGroup = room.roomType == ChatRoomType.maviGroup;
    final candidates = isMaviGroup
        ? directory.mavi.map((u) => (id: u.userId, title: u.fullName, subtitle: 'MAVI')).toList()
        : directory.partners
            .map((p) => (
                  id: p.userId,
                  title: p.fullName,
                  subtitle: p.partnerName,
                ))
            .toList();

    final result = await showChatCreateGroupSheet(
      context: context,
      headline: 'Inviter til ${room.displayTitle()}',
      privacyHint: 'Velg hvem som skal legges til i gruppen.',
      candidates: candidates,
      currentUserId: '',
      minMembers: 1,
      titleOptional: true,
      initialTitle: room.displayTitle(),
      confirmLabel: 'Inviter',
    );
    if (result == null || result.memberIds.isEmpty) return;

    try {
      final n = await PartnerChatService.superadminInviteToRoom(
        roomId: room.id,
        userIds: result.memberIds,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Inviterte $n bruker(e)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke invitere: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.indigo.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.admin_panel_settings_outlined, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Superadmin — chat-kontroll',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${directory.mavi.length} MAVI · ${directory.partners.length} partnere · '
              '${directory.companies.length} bedrifter',
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('MAVI-gruppe'),
                  onPressed: () => _createMaviGroup(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Partner-gruppe'),
                  onPressed: () => _createPartnerGroup(context),
                ),
                ActionChip(
                  avatar: Icon(Icons.link, size: 18, color: DriftProTheme.primaryGreen),
                  label: const Text('Koble MAVI↔partner'),
                  onPressed: () => _bridgePartner(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Inviter til gruppe'),
                  onPressed: () => _inviteToRoom(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
