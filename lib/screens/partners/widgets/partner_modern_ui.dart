import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'eco_driving_badge.dart';

/// Nøytralt, moderne UI for bedrifter — uten sterke gradienter.
class PartnerModernUi {
  PartnerModernUi._();

  static Color border(BuildContext context) => context.driftColors.border;

  static Color surface(BuildContext context) => context.driftColors.card;

  static Color muted(BuildContext context) => context.driftColors.textMuted;

  static Color textPrimary(BuildContext context) => context.driftColors.textPrimary;

  static Color accent(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF90CDF4) : const Color(0xFF374151);
}

class PartnerModernPageHeader extends StatelessWidget {
  const PartnerModernPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: PartnerModernUi.textPrimary(context),
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: TextStyle(fontSize: 13, color: PartnerModernUi.muted(context), height: 1.35)),
                ],
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class PartnerModernCompanyRow extends StatelessWidget {
  const PartnerModernCompanyRow({
    super.key,
    required this.name,
    required this.metaLine,
    required this.maviCodes,
    required this.maviCount,
    required this.onTap,
    this.note,
    this.isActive = true,
    this.matchHint,
  });

  final String name;
  final String metaLine;
  final List<String> maviCodes;
  final int maviCount;
  final VoidCallback onTap;
  final String? note;
  final bool isActive;
  final String? matchHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PartnerModernUi.border(context)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PartnerModernUi.border(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: PartnerModernUi.textPrimary(context),
                              ),
                            ),
                          ),
                          if (!isActive)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: PartnerModernUi.border(context),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Inaktiv', style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                      ),
                      if (maviCodes.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _MaviChips(codes: maviCodes),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Ingen MAVI',
                            style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                          ),
                        ),
                      if (note != null && note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          note!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: PartnerModernUi.muted(context)),
                        ),
                      ],
                      if (matchHint != null) ...[
                        const SizedBox(height: 2),
                        Text(matchHint!, style: TextStyle(fontSize: 9, color: PartnerModernUi.accent(context))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$maviCount',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    Text('MAVI', style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
                  ],
                ),
                Icon(Icons.chevron_right, size: 18, color: PartnerModernUi.muted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MaviChips extends StatelessWidget {
  const _MaviChips({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final show = codes.length > 4 ? codes.take(3).toList() : codes;
    final extra = codes.length - show.length;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        ...show.map(
          (c) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: PartnerModernUi.border(context),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              c,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: PartnerModernUi.textPrimary(context),
              ),
            ),
          ),
        ),
        if (extra > 0)
          Text('+$extra', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
      ],
    );
  }
}

class PartnerModernKpiGrid extends StatelessWidget {
  const PartnerModernKpiGrid({super.key, required this.items});

  final List<(String label, String value)> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: PartnerModernUi.surface(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PartnerModernUi.border(context)),
                ),
                child: Column(
                  children: [
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items[i].$1,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PartnerModernSearchBar extends StatelessWidget {
  const PartnerModernSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: PartnerModernUi.muted(context), fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: PartnerModernUi.muted(context)),
          suffixIcon: onClear != null
              ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear)
              : null,
          filled: true,
          fillColor: PartnerModernUi.surface(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: PartnerModernUi.border(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: PartnerModernUi.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: PartnerModernUi.accent(context)),
          ),
        ),
      ),
    );
  }
}

class PartnerModernDetailHeader extends StatelessWidget {
  const PartnerModernDetailHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.maviCount,
    required this.regCount,
    required this.isActive,
    required this.onActiveChanged,
    this.canToggleActive = true,
    this.ecoDrivingStatus,
    this.ecoDrivingDeadline,
    this.ecoDrivingCompletedAt,
    this.smsCount,
    this.portalCount,
  });

  final String title;
  final String subtitle;
  final int maviCount;
  final int regCount;
  final bool isActive;
  final ValueChanged<bool>? onActiveChanged;
  final bool canToggleActive;
  final EcoDrivingStatus? ecoDrivingStatus;
  final DateTime? ecoDrivingDeadline;
  final DateTime? ecoDrivingCompletedAt;
  final int? smsCount;
  final int? portalCount;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerModernUi.muted(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: PartnerModernUi.border(context).withValues(alpha: 0.85),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        height: 1.15,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, height: 1.35, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isActive ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isActive ? 'Aktiv' : 'Deaktivert',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isActive ? const Color(0xFF15803D) : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              if (canToggleActive && onActiveChanged != null) ...[
                const SizedBox(width: 4),
                Switch(
                  value: isActive,
                  onChanged: onActiveChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _kpi(context, 'MAVI', '$maviCount', const Color(0xFF15803D))),
              const SizedBox(width: 8),
              Expanded(child: _kpi(context, 'Skilt', '$regCount', const Color(0xFF2563EB))),
              const SizedBox(width: 8),
              Expanded(
                child: _kpi(
                  context,
                  'SMS',
                  '${smsCount ?? '—'}',
                  const Color(0xFF7C3AED),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kpi(
                  context,
                  'Portal',
                  portalCount == null
                      ? '—'
                      : (portalCount == 0 ? '0' : '$portalCount'),
                  const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          if (ecoDrivingStatus != null) ...[
            const SizedBox(height: 12),
            EcoDrivingBadge(
              status: ecoDrivingStatus!,
              prominent: true,
              deadline: ecoDrivingDeadline,
              completedAt: ecoDrivingCompletedAt,
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: PartnerModernUi.muted(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: color,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class PartnerModernSection extends StatelessWidget {
  const PartnerModernSection({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.initiallyExpanded = false,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  /// Beholdt for bakoverkompatibilitet — paneler er alltid synlige.
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final muted = PartnerModernUi.muted(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: PartnerModernUi.border(context).withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: DriftProTheme.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: -0.2,
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(
            height: 1,
            color: PartnerModernUi.border(context).withValues(alpha: 0.7),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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

/// Konsistent tekstfelt for partner-workspace (tettere, tydeligere).
class PartnerWorkspaceField extends StatelessWidget {
  const PartnerWorkspaceField({
    super.key,
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
    this.hint,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: PartnerModernUi.textPrimary(context),
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: PartnerModernUi.border(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: PartnerModernUi.border(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: DriftProTheme.primaryGreen, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class PartnerSmartAction {
  const PartnerSmartAction({
    required this.label,
    required this.icon,
    this.hint,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final String? hint;
  final VoidCallback? onTap;
}

class PartnerSmartActionsPanel extends StatelessWidget {
  const PartnerSmartActionsPanel({
    super.key,
    required this.title,
    required this.actions,
  });

  final String title;
  final List<PartnerSmartAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          ...actions.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: PartnerModernUi.border(context).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Icon(a.icon, size: 16, color: PartnerModernUi.muted(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: PartnerModernUi.textPrimary(context),
                                ),
                              ),
                              if (a.hint != null)
                                Text(
                                  a.hint!,
                                  style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PartnerSmartSectionPicker extends StatelessWidget {
  const PartnerSmartSectionPicker({
    super.key,
    required this.title,
    required this.currentLabel,
    required this.onPick,
    required this.onToggleAll,
    required this.showAll,
  });

  final String title;
  final String currentLabel;
  final VoidCallback onPick;
  final VoidCallback onToggleAll;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$title: $currentLabel',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PartnerModernUi.textPrimary(context),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: const Text('Bytt'),
          ),
          IconButton(
            onPressed: onToggleAll,
            tooltip: showAll ? 'Skjul alle seksjoner' : 'Vis alle seksjoner',
            icon: Icon(showAll ? Icons.expand_less : Icons.expand_more),
          ),
        ],
      ),
    );
  }
}

class PartnerModernSegmented<T> extends StatelessWidget {
  const PartnerModernSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: options.map((o) {
          final sel = o == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: sel ? PartnerModernUi.textPrimary(context) : PartnerModernUi.surface(context),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(o),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PartnerModernUi.border(context)),
                  ),
                  child: Text(
                    labelOf(o),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : PartnerModernUi.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Viser alle MAVI-biler med kode, skilt, sjåfør, biltype og sist bilkontroll.
class PartnerMaviVehicleOverview extends StatelessWidget {
  const PartnerMaviVehicleOverview({
    super.key,
    required this.vehicles,
    this.dense = false,
    this.muted = false,
    this.lastInspectionByVehicleId = const {},
  });

  final List<PartnerVehicle> vehicles;
  final bool dense;
  final bool muted;
  final Map<String, PartnerVehicleInspection> lastInspectionByVehicleId;

  static List<PartnerVehicle> filterMavi(
    Iterable<PartnerVehicle> all, {
    bool includeInactive = false,
  }) {
    final list = all
        .where(
          (v) =>
              (includeInactive || v.isActive) &&
              v.vehicleKind != 'registration' &&
              !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode),
        )
        .toList()
      ..sort(
        (a, b) => MaviUnitCodes.normalize(a.unitCode).compareTo(
              MaviUnitCodes.normalize(b.unitCode),
            ),
      );
    return list;
  }

  String _subtitle(PartnerVehicle v) {
    final parts = <String>[];
    final plate = v.registrationNumber.trim();
    if (plate.isNotEmpty && plate != MaviUnitCodes.regNrPlaceholder) {
      parts.add(plate);
    }
    final driver = v.driverName?.trim();
    if (driver != null && driver.isNotEmpty) {
      parts.add(driver);
    }
    final roles = v.fleetRolesLabel;
    if (roles != 'Uten type') {
      parts.add(roles);
    }
    if (parts.isEmpty) return 'Uten skilt eller sjåfør';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      return Text(
        'Ingen MAVI — trykk for å legge til',
        style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MAVI-biler (${vehicles.length})',
          style: TextStyle(
            fontSize: dense ? 10 : 11,
            fontWeight: FontWeight.w700,
            color: PartnerModernUi.textPrimary(context).withValues(alpha: 0.78),
          ),
        ),
        SizedBox(height: dense ? 4 : 6),
        ...vehicles.map((v) => _vehicleRow(context, v)),
      ],
    );
  }

  Widget _vehicleRow(BuildContext context, PartnerVehicle v) {
    final code = MaviUnitCodes.normalize(v.unitCode);
    final gray = muted || !v.isActive;
    final accent = gray ? const Color(0xFF9CA3AF) : const Color(0xFF15803D);
    final last = v.id.isNotEmpty ? lastInspectionByVehicleId[v.id] : null;
    // Vis kun badge når bilen faktisk er kontrollert (skjul «Ikke kontrollert»).
    final showInspection = last != null;
    final inspectionLabel = showInspection ? _inspectionLabel(last) : null;
    final inspectionColor = showInspection ? _inspectionColor(last, gray) : null;

    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 4 : 6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10,
          vertical: dense ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: PartnerModernUi.border(context).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: PartnerModernUi.border(context).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Text(
                MaviUnitCodes.compactLabel(code),
                style: TextStyle(
                  fontSize: dense ? 10 : 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                  Text(
                    _subtitle(v),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 9 : 10,
                      height: 1.25,
                      color: PartnerModernUi.muted(context),
                    ),
                  ),
                ],
              ),
            ),
            if (showInspection && inspectionLabel != null && inspectionColor != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: inspectionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: inspectionColor.withValues(alpha: 0.28)),
                ),
                child: Text(
                  inspectionLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: dense ? 9 : 10,
                    fontWeight: FontWeight.w700,
                    color: inspectionColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _inspectionLabel(PartnerVehicleInspection last) {
    final d = last.inspectedAt.toLocal();
    final stamp =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    if (last.hasDeviation) return 'Avvik · $stamp';
    return 'OK · $stamp';
  }

  Color _inspectionColor(PartnerVehicleInspection last, bool gray) {
    if (gray) return const Color(0xFF9CA3AF);
    if (last.hasDeviation) return const Color(0xFFDC2626);
    return const Color(0xFF15803D);
  }
}
