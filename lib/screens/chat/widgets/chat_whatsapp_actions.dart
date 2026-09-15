import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/chat/partner_chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/chat/chat_models.dart';
import 'chat_ui_helpers.dart';

/// WhatsApp-stil: emoji-bar + handlingsmeny over mørklagt chat.
Future<void> showChatWhatsAppActions({
  required BuildContext context,
  required bool mine,
  required Widget messagePreview,
  void Function(String emoji)? onReact,
  VoidCallback? onReply,
  VoidCallback? onPrivate,
  VoidCallback? onCopy,
  VoidCallback? onPin,
  VoidCallback? onReport,
  VoidCallback? onShowRead,
  VoidCallback? onDelete,
  VoidCallback? onSuperAdminDelete,
  VoidCallback? onHide,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Lukk',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, secondary) {
      return SafeArea(
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(ctx),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
                child: GestureDetector(
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                        mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      _EmojiReactionBar(
                        onPick: (e) {
                          Navigator.pop(ctx);
                          onReact?.call(e);
                        },
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
                        ),
                        child: messagePreview,
                      ),
                      const SizedBox(height: 10),
                      _WhatsAppActionMenu(
                        mine: mine,
                        onReply: _wrap(ctx, onReply),
                        onPrivate: _wrap(ctx, onPrivate),
                        onCopy: _wrap(ctx, onCopy),
                        onPin: _wrap(ctx, onPin),
                        onReport: _wrap(ctx, onReport),
                        onShowRead: _wrap(ctx, onShowRead),
                        onDelete: _wrap(ctx, onDelete),
                        onSuperAdminDelete: _wrap(ctx, onSuperAdminDelete),
                        onHide: _wrap(ctx, onHide),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

VoidCallback? _wrap(BuildContext ctx, VoidCallback? action) {
  if (action == null) return null;
  return () {
    Navigator.pop(ctx);
    action();
  };
}

class _EmojiReactionBar extends StatelessWidget {
  const _EmojiReactionBar({required this.onPick});

  final void Function(String emoji) onPick;

  Future<void> _openLibrary(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.55,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Alle emoji',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: PartnerChatService.reactionEmojiLibrary.length,
                    itemBuilder: (_, i) {
                      final e = PartnerChatService.reactionEmojiLibrary[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(ctx, e),
                        child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 36,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (final e in PartnerChatService.quickReactionEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onPick(e),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openLibrary(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppActionMenu extends StatelessWidget {
  const _WhatsAppActionMenu({
    required this.mine,
    this.onReply,
    this.onPrivate,
    this.onCopy,
    this.onPin,
    this.onReport,
    this.onShowRead,
    this.onDelete,
    this.onSuperAdminDelete,
    this.onHide,
  });

  final bool mine;
  final VoidCallback? onReply;
  final VoidCallback? onPrivate;
  final VoidCallback? onCopy;
  final VoidCallback? onPin;
  final VoidCallback? onReport;
  final VoidCallback? onShowRead;
  final VoidCallback? onDelete;
  final VoidCallback? onSuperAdminDelete;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    void add(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      Color? color,
      bool danger = false,
    }) {
      if (onTap == null) return;
      if (items.isNotEmpty) {
        items.add(Divider(height: 1, thickness: 0.5, color: Colors.grey.shade200));
      }
      items.add(
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: danger
                          ? const Color(0xFFE11D48)
                          : (color ?? const Color(0xFF111111)),
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: 22,
                  color: danger ? const Color(0xFFE11D48) : Colors.grey.shade700,
                ),
              ],
            ),
          ),
        ),
      );
    }

    add(Icons.reply_rounded, 'Svar', onReply);
    add(Icons.lock_outline_rounded, 'Send privat', onPrivate, color: const Color(0xFF7C3AED));
    add(Icons.copy_rounded, 'Kopier', onCopy);
    add(Icons.push_pin_outlined, 'Fest', onPin);
    add(Icons.done_all_rounded, 'Lest av', onShowRead);
    add(Icons.flag_outlined, 'Rapporter', onReport, color: Colors.orange.shade800);
    add(Icons.visibility_off_outlined, 'Skjul (moderator)', onHide, color: Colors.orange.shade800);
    if (mine) {
      add(Icons.delete_outline, 'Slett', onDelete, danger: true);
    } else {
      add(Icons.delete_forever_outlined, 'Slett (superadmin)', onSuperAdminDelete, danger: true);
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

/// Sheet som viser hvem som reagerte (WhatsApp-stil).
Future<void> showChatReactionDetails({
  required BuildContext context,
  required List<ChatReactionGroup> reactions,
  void Function(String emoji)? onToggle,
}) {
  if (reactions.isEmpty) return Future.value();

  var selected = 'all';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final total = reactions.fold<int>(0, (s, r) => s + r.count);
          final visible = selected == 'all'
              ? reactions
              : reactions.where((g) => g.emoji == selected).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 8,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Text(
                    '$total reaksjon${total == 1 ? '' : 'er'}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        _ReactionTab(
                          label: 'Alle',
                          selected: selected == 'all',
                          onTap: () => setLocal(() => selected = 'all'),
                        ),
                        for (final g in reactions)
                          _ReactionTab(
                            label: '${g.emoji} ${g.count}',
                            selected: selected == g.emoji,
                            onTap: () => setLocal(() => selected = g.emoji),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final g in visible)
                          for (final name in g.userNames)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    ChatUiHelpers.senderColor(name).withValues(alpha: 0.15),
                                child: Text(
                                  (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: ChatUiHelpers.senderColor(name),
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              trailing: Text(g.emoji, style: const TextStyle(fontSize: 22)),
                              onTap: g.mine && onToggle != null
                                  ? () {
                                      Navigator.pop(ctx);
                                      onToggle(g.emoji);
                                    }
                                  : null,
                              subtitle: g.mine
                                  ? const Text(
                                      'Din reaksjon — trykk for å fjerne',
                                      style: TextStyle(fontSize: 12),
                                    )
                                  : null,
                            ),
                      ],
                    ),
                  ),
                  if (onToggle != null) ...[
                    const Divider(),
                    Text(
                      'Legg til reaksjon',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final e in PartnerChatService.quickReactionEmojis)
                          IconButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onToggle(e);
                            },
                            icon: Text(e, style: const TextStyle(fontSize: 24)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _ReactionTab extends StatelessWidget {
  const _ReactionTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? DriftProTheme.primaryGreen : Colors.black87,
        ),
      ),
    );
  }
}
