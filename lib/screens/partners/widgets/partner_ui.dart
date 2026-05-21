import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Delte UI-komponenter for bedrifter / samarbeidspartnere.
class PartnerUi {
  PartnerUi._();

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 720;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? DriftProTheme.cardDark
          : DriftProTheme.cardLight;

  static Color mutedText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.grey[400]! : Colors.grey[600]!;
}

class PartnerHeroBanner extends StatelessWidget {
  const PartnerHeroBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, compact ? 8 : 12),
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        gradient: DriftProTheme.cardGradient,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        boxShadow: DriftProTheme.elevatedShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: compact ? 10 : 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DriftProTheme.headingMd.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: DriftProTheme.bodySm.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class PartnerKpiStrip extends StatelessWidget {
  const PartnerKpiStrip({super.key, required this.items});

  final List<PartnerKpiItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _PartnerKpiTile(item: items[i]),
      ),
    );
  }
}

class PartnerKpiItem {
  const PartnerKpiItem({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;
}

class _PartnerKpiTile extends StatelessWidget {
  const _PartnerKpiTile({required this.item});

  final PartnerKpiItem item;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 118,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: item.color.withValues(alpha: 0.22)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.icon != null) Icon(item.icon, size: 16, color: item.color),
          if (item.icon != null) const SizedBox(height: 6),
          Text(
            item.value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: item.color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DriftProTheme.labelSm.copyWith(
              color: PartnerUi.mutedText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (item.onTap == null) return child;
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
      child: child,
    );
  }
}

class PartnerSearchPanel extends StatelessWidget {
  const PartnerSearchPanel({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
    this.hintChips = const [],
    this.trailingChip,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final List<(String label, VoidCallback onTap)> hintChips;
  final Widget? trailingChip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.22)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search_rounded, color: DriftProTheme.primaryGreen),
              suffixIcon: onClear != null
                  ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClear)
                  : null,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: onChanged,
          ),
          if (hintChips.isNotEmpty || trailingChip != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...hintChips.map(
                  (c) => ActionChip(
                    label: Text(c.$1, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.07),
                    side: BorderSide(color: DriftProTheme.primaryGreen.withValues(alpha: 0.18)),
                    onPressed: c.$2,
                  ),
                ),
                if (trailingChip != null) trailingChip!,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PartnerStatusBadge extends StatelessWidget {
  const PartnerStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class PartnerMetaRow extends StatelessWidget {
  const PartnerMetaRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: PartnerUi.mutedText(context)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text.isEmpty ? '—' : text,
            overflow: TextOverflow.ellipsis,
            style: DriftProTheme.bodySm.copyWith(color: PartnerUi.mutedText(context)),
          ),
        ),
      ],
    );
  }
}

class PartnerSectionCard extends StatelessWidget {
  const PartnerSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.children = const [],
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final accent = iconColor ?? DriftProTheme.primaryGreen;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                if (icon != null) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: DriftProTheme.headingSm),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle!,
                            style: DriftProTheme.caption.copyWith(height: 1.35),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: padding.copyWith(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class PartnerEmptyState extends StatelessWidget {
  const PartnerEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: DriftProTheme.primaryGreen.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: DriftProTheme.headingSm),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: DriftProTheme.caption.copyWith(height: 1.4),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class PartnerStickySaveBar extends StatelessWidget {
  const PartnerStickySaveBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PartnerUi.surface(context).withValues(alpha: 0.96),
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.18))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                if (secondary != null) ...[secondary!, const SizedBox(width: 10)],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: loading ? null : onPressed,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(label),
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      minimumSize: const Size(0, 48),
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

class PartnerDetailTabBar extends StatelessWidget {
  const PartnerDetailTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<(IconData icon, String label)> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DriftProTheme.radiusSm),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        labelColor: Theme.of(context).colorScheme.onSurface,
        unselectedLabelColor: PartnerUi.mutedText(context),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(6),
        labelStyle: DriftProTheme.labelSm,
        tabs: tabs
            .map(
              (t) => Tab(
                height: 40,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.$1, size: 16),
                    const SizedBox(width: 6),
                    Text(t.$2),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class PartnerInlineField extends StatelessWidget {
  const PartnerInlineField({
    super.key,
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
