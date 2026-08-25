import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bil-eier har få hovedfaner — sekundære under «Mer».
/// Horisontal scroll viser alle ikoner hele tiden.
class PartnerPortalNavItem {
  const PartnerPortalNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
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
  static const _itemWidth = 76.0;

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
    final target = (i * _itemWidth - 40).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.cardDark : Colors.white;

    return Material(
      color: bg,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final item = widget.items[i];
              final selected = i == widget.selectedIndex;
              final fg = selected ? DriftProTheme.primaryGreen : (isDark ? Colors.white70 : Colors.grey.shade700);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onSelected(i),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: _itemWidth,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.22 : 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? item.selectedIcon : item.icon,
                          size: 22,
                          color: fg,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                            color: fg,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
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
