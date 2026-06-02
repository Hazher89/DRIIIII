import 'package:flutter/material.dart';

/// Nøytralt, moderne UI for bedrifter — uten sterke gradienter.
class PartnerModernUi {
  PartnerModernUi._();

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2D3748)
          : const Color(0xFFE5E7EB);

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A202C) : Colors.white;

  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFA0AEC0) : const Color(0xFF6B7280);

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF7FAFC) : const Color(0xFF111827);

  static Color accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF90CDF4) : const Color(0xFF374151);
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
  });

  final String title;
  final String subtitle;
  final int maviCount;
  final int regCount;
  final bool isActive;
  final ValueChanged<bool>? onActiveChanged;
  final bool canToggleActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PartnerModernUi.border(context)),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context))),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isActive ? 'Aktiv' : 'Av', style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
                  Switch(
                    value: isActive,
                    onChanged: canToggleActive ? onActiveChanged : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill(context, '$maviCount MAVI'),
              const SizedBox(width: 8),
              _pill(context, '$regCount reg.nr'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: PartnerModernUi.textPrimary(context))),
    );
  }
}

class PartnerModernSection extends StatelessWidget {
  const PartnerModernSection({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.initiallyExpanded = false,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: PartnerModernUi.textPrimary(context))),
          subtitle: subtitle != null
              ? Text(subtitle!, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)))
              : null,
          trailing: trailing,
          children: children,
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
