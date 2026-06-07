import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/permissions/permission_gate.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/ticket.dart';
import '../../../models/user_profile.dart';
import '../dashboard_search_catalog.dart';

class DashboardCommandPalette extends StatefulWidget {
  final UserProfile profile;
  final List<Ticket> scopedTickets;
  final List<Absence> scopedAbsences;
  final NavigateByAccess? onNavigateByAccess;

  const DashboardCommandPalette({
    super.key,
    required this.profile,
    required this.scopedTickets,
    required this.scopedAbsences,
    this.onNavigateByAccess,
  });

  static Future<void> show(
    BuildContext context, {
    required UserProfile profile,
    required List<Ticket> scopedTickets,
    required List<Absence> scopedAbsences,
    NavigateByAccess? onNavigateByAccess,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? DriftProTheme.cardDark
          : Colors.white,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DashboardCommandPalette(
          profile: profile,
          scopedTickets: scopedTickets,
          scopedAbsences: scopedAbsences,
          onNavigateByAccess: onNavigateByAccess,
        ),
      ),
    );
  }

  @override
  State<DashboardCommandPalette> createState() => _DashboardCommandPaletteState();
}

class _DashboardCommandPaletteState extends State<DashboardCommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _controller.addListener(() => setState(() => _query = _controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<DashboardSearchItem> get _results {
    return DashboardSearchCatalog.search(
      profile: widget.profile,
      access: widget.profile.access,
      query: _query,
      tickets: widget.scopedTickets,
      absences: widget.scopedAbsences,
      go: widget.onNavigateByAccess,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final results = _results;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Søk moduler, handlinger og dine data…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _controller.clear(),
                      ),
                filled: true,
                fillColor: isDark ? DriftProTheme.surfaceDark : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Viser kun det du har tilgang til — ingen treff utenfor dine rettigheter.',
                    style: DriftProTheme.caption.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          _query.trim().isEmpty
                              ? 'Skriv for å finne sider og funksjoner'
                              : 'Ingen treff for «$_query»',
                          textAlign: TextAlign.center,
                          style: DriftProTheme.bodyMd,
                        ),
                        if (_query.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Moduler du ikke har tilgang til vises aldri.',
                            textAlign: TextAlign.center,
                            style: DriftProTheme.caption,
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.icon,
                              color: DriftProTheme.primaryGreen, size: 20),
                        ),
                        title: Text(item.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${item.category} · ${item.subtitle}'),
                        trailing: _kindBadge(item.kind),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                          item.navigate(context, widget.onNavigateByAccess);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kindBadge(DashboardSearchKind kind) {
    final (label, color) = switch (kind) {
      DashboardSearchKind.module => ('Modul', DriftProTheme.accentBlue),
      DashboardSearchKind.action => ('Handling', DriftProTheme.primaryGreen),
      DashboardSearchKind.liveData => ('Data', DriftProTheme.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
