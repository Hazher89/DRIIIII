import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bil-eier har få hovedfaner — sekundære under «Mer».
/// Horisontal scroll viser alle ikoner hele tiden.
class PartnerPortalNavItem {
  const PartnerPortalNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

class PartnerPortalBottomNav extends StatefulWidget {
  const PartnerPortalBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<PartnerPortalNavItem> items;

  @override
  State<PartnerPortalBottomNav> createState() => _PartnerPortalBottomNavState();
}

class _PartnerPortalBottomNavState extends State<PartnerPortalBottomNav> {
  final _scroll = ScrollController();
  static const _itemWidth = 78.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PartnerPortalBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    if (!_scroll.hasClients) return;
    final i = widget.selectedIndex.clamp(0, widget.items.length - 1);
    final target = (i * _itemWidth - 48).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.cardDark : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final item = widget.items[i];
              final selected = i == widget.selectedIndex;
              final fg = selected
                  ? DriftProTheme.primaryGreen
                  : (isDark ? Colors.white60 : Colors.grey.shade600);

              return Semantics(
                button: true,
                selected: selected,
                label: item.label,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onSelected(i),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: _itemWidth,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.24 : 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: selected
                            ? Border.all(
                                color: DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.35 : 0.2),
                              )
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: selected ? 1.06 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            child: Badge(
                              isLabelVisible: item.badgeCount > 0,
                              backgroundColor: DriftProTheme.error,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              label: Text(
                                item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                              ),
                              child: Icon(
                                selected ? item.selectedIcon : item.icon,
                                size: 23,
                                color: fg,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                              color: fg,
                              letterSpacing: selected ? 0.1 : 0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
