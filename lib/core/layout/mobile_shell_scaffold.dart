import 'package:flutter/material.dart';

import '../config/driftpro_client.dart';
import '../theme/driftpro_theme_context.dart';
import 'mobile_layout.dart';

/// Pull-to-refresh for fane-innhold uten egen scroll (tomme tilstander).
class MobilePullRefresh extends StatelessWidget {
  const MobilePullRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (child is ScrollView) {
      return RefreshIndicator(onRefresh: onRefresh, child: child);
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverFillRemaining(hasScrollBody: false, child: child),
        ],
      ),
    );
  }
}

bool _isRefreshIconButton(Widget widget) {
  if (widget is! IconButton) return false;
  final icon = widget.icon;
  if (icon is! Icon || icon.icon == null) return false;
  return {
    Icons.refresh,
    Icons.refresh_rounded,
    Icons.refresh_outlined,
  }.contains(icon.icon);
}

List<Widget>? _mobileActionsWithoutRefresh(List<Widget>? actions) {
  if (actions == null || actions.isEmpty) return actions;
  final filtered = actions.where((w) => !_isRefreshIconButton(w)).toList();
  return filtered.isEmpty ? null : filtered;
}

/// Kompakt side-header under DriftPro-logo på native app (erstatter AppBar).
class MobileShellPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const MobileShellPageHeader({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  static const _height = 44.0;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Material(
      color: drift.surface,
      child: Container(
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: drift.borderSubtle)),
        ),
        child: Row(
          children: [
            if (leading != null) leading!,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: drift.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }
}

/// Scaffold for faner i [MainShell] — unngår dobbel header (logo + AppBar) på mobil.
class MobileShellScaffold extends StatelessWidget {
  const MobileShellScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.hideMobileTitleBar = false,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;

  /// Skjuler tittel-/handlings-raden på mobil (faner under logo er nok).
  final bool hideMobileTitleBar;

  bool _showHeader(List<Widget>? effectiveActions) =>
      title != null && title!.isNotEmpty ||
      (effectiveActions != null && effectiveActions.isNotEmpty) ||
      leading != null;

  @override
  Widget build(BuildContext context) {
    final mobileActions =
        DriftProClient.isMobile ? _mobileActionsWithoutRefresh(actions) : actions;

    if (!DriftProClient.isMobile) {
      final hasAppBar = _showHeader(actions) || bottom != null;
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: hasAppBar
            ? AppBar(
                title: title != null ? Text(title!) : null,
                actions: actions,
                bottom: bottom,
                // Unngå tom toolbar-høyde når kun faner vises (store gap under logo).
                toolbarHeight: _showHeader(actions) ? kToolbarHeight : 0,
                automaticallyImplyLeading: false,
                scrolledUnderElevation: 0,
              )
            : null,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    final showHeader = !hideMobileTitleBar && _showHeader(mobileActions);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            MobileShellPageHeader(
              title: title ?? '',
              actions: mobileActions,
              leading: leading,
            ),
          if (bottom != null) bottom!,
          Expanded(child: body),
        ],
      ),
      floatingActionButton: MobileLayout.wrapFab(context, floatingActionButton),
      floatingActionButtonLocation:
          floatingActionButtonLocation ?? MobileLayout.fabLocation,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Fullskjerm-sider (root navigator) — kompakt AppBar på mobil, uendret på web.
class MobileAppScaffold extends StatelessWidget {
  const MobileAppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottom,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.leading,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: title != null || bottom != null
          ? AppBar(
              leading: leading,
              primary: !DriftProClient.isMobile,
              title: title != null ? Text(title!) : null,
              actions: actions,
              bottom: bottom,
              toolbarHeight: DriftProClient.isMobile ? 48 : null,
              titleSpacing: DriftProClient.isMobile ? 0 : null,
            )
          : null,
      body: body,
      floatingActionButton: MobileLayout.wrapFab(context, floatingActionButton),
      floatingActionButtonLocation:
          floatingActionButtonLocation ?? MobileLayout.fabLocation,
    );
  }
}
