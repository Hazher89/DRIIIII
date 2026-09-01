import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';

enum ChatAttachAction { photo, video, document, location }

enum ChatRoomMenuAction {
  search,
  mediaGallery,
  members,
  darkMode,
  pinRoom,
  muteRoom,
  schedule,
  template,
  selfDestruct,
  translation,
  toggleTranslation,
  subgroup,
  stats,
  archive,
}

class ChatAttachSheet extends StatelessWidget {
  const ChatAttachSheet({super.key});

  static Future<ChatAttachAction?> show(BuildContext context) {
    return showModalBottomSheet<ChatAttachAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ChatAttachSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Legg ved',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Velg hva du vil dele i samtalen',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _AttachTile(
                    icon: Icons.photo_library_rounded,
                    label: 'Bilde',
                    color: Colors.blue.shade600,
                    onTap: () => Navigator.pop(context, ChatAttachAction.photo),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AttachTile(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    color: Colors.purple.shade600,
                    onTap: () => Navigator.pop(context, ChatAttachAction.video),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _AttachTile(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Dokument',
                    color: Colors.orange.shade700,
                    onTap: () => Navigator.pop(context, ChatAttachAction.document),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AttachTile(
                    icon: Icons.location_on_rounded,
                    label: 'Posisjon',
                    color: Colors.red.shade600,
                    onTap: () => Navigator.pop(context, ChatAttachAction.location),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatRoomMenuSheet extends StatelessWidget {
  const ChatRoomMenuSheet({
    super.key,
    required this.room,
    required this.pinned,
    required this.muted,
    required this.darkMode,
    required this.showTranslation,
    required this.canSend,
    required this.canModerateMessages,
    required this.isGroup,
  });

  final ChatRoom room;
  final bool pinned;
  final bool muted;
  final bool darkMode;
  final bool showTranslation;
  final bool canSend;
  final bool canModerateMessages;
  final bool isGroup;

  static Future<ChatRoomMenuAction?> show(
    BuildContext context, {
    required ChatRoom room,
    required bool pinned,
    required bool muted,
    required bool darkMode,
    required bool showTranslation,
    required bool canSend,
    required bool canModerateMessages,
    required bool isGroup,
  }) {
    return showModalBottomSheet<ChatRoomMenuAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChatRoomMenuSheet(
        room: room,
        pinned: pinned,
        muted: muted,
        darkMode: darkMode,
        showTranslation: showTranslation,
        canSend: canSend,
        canModerateMessages: canModerateMessages,
        isGroup: isGroup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.displayTitle(),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                Text(
                  room.roomType.subtitleNorwegian,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          _section('Finn og se'),
          _item(
            icon: Icons.search_rounded,
            label: 'Søk i samtale',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.search),
          ),
          _item(
            icon: Icons.perm_media_outlined,
            label: 'Media i samtalen',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.mediaGallery),
          ),
          _item(
            icon: Icons.people_outline,
            label: 'Medlemmer',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.members),
          ),
          _section('Samtale'),
          _item(
            icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: pinned ? 'Løsne samtale' : 'Fest samtale',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.pinRoom),
          ),
          _item(
            icon: muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            label: muted ? 'Slå på varsler' : 'Demp varsler',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.muteRoom),
          ),
          _item(
            icon: Icons.archive_outlined,
            label: 'Arkiver samtale',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.archive),
          ),
          if (canSend) ...[
            _section('Melding'),
            _item(
              icon: Icons.schedule_send_outlined,
              label: 'Planlegg melding',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.schedule),
            ),
            _item(
              icon: Icons.bolt_outlined,
              label: 'Hurtigmal',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.template),
            ),
            _item(
              icon: Icons.timer_outlined,
              label: 'Selvdestruerende melding',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.selfDestruct),
            ),
            _item(
              icon: Icons.translate_rounded,
              label: 'Legg til oversettelse',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.translation),
            ),
            _item(
              icon: Icons.language_rounded,
              label: showTranslation ? 'Vis original' : 'Vis oversettelse',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.toggleTranslation),
            ),
          ],
          if (isGroup)
            _item(
              icon: Icons.group_add_outlined,
              label: 'Opprett undergruppe',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.subgroup),
            ),
          _section('Utseende'),
          _item(
            icon: darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            label: darkMode ? 'Lys modus' : 'Mørk modus',
            onTap: () => Navigator.pop(context, ChatRoomMenuAction.darkMode),
          ),
          if (canModerateMessages) ...[
            _section('Admin'),
            _item(
              icon: Icons.insights_outlined,
              label: 'Statistikk',
              onTap: () => Navigator.pop(context, ChatRoomMenuAction.stats),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: DriftProTheme.primaryGreen),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
