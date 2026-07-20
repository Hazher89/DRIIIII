import 'package:flutter/material.dart';

import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/routing/route_url_sync.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/time_clock/time_clock_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../core/permissions/permission_gate.dart';
import 'tabs/time_clock_mobile_tab.dart';
import 'tabs/time_clock_presence_tab.dart';
import 'tabs/time_clock_settings_tab.dart';
import 'tabs/time_clock_timesheet_tab.dart';

class StemplingScreen extends StatefulWidget {
  const StemplingScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<StemplingScreen> createState() => _StemplingScreenState();
}

class _StemplingScreenState extends State<StemplingScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  UserProfile? _profile;
  bool _loading = true;
  bool _mobileAllowed = false;
  String? _pendingTab;

  bool get _isAdmin =>
      _profile?.access.canStemplingAdmin == true ||
      _profile?.isSuperAdmin == true ||
      _profile?.isAdmin == true ||
      _profile?.role == UserRole.leder;

  bool get _canEditAll => _profile?.isSuperAdmin == true || _profile?.isAdmin == true;

  bool get _canSettings =>
      _profile?.access.canStemplingSettings == true ||
      _profile?.isSuperAdmin == true ||
      _profile?.isAdmin == true;

  @override
  void initState() {
    super.initState();
    _pendingTab = widget.initialTab;
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      final mobile = profile != null
          ? await TimeClockService.hasMobileAccess()
          : false;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _mobileAllowed = mobile;
        _loading = false;
      });
      _initTabs();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _initTabs() {
    _tabController?.dispose();
    final tabs = _buildTabDefs();
    final initial = _indexForSlug(_pendingTab, tabs.length);
    _tabController = TabController(length: tabs.length, vsync: this, initialIndex: initial);
    _tabController!.addListener(_onTabChanged);
    _pendingTab = null;
    setState(() {});
  }

  List<({String slug, String label, Widget child})> _buildTabDefs() {
    final p = _profile;
    if (p == null) return [];

    final tabs = <({String slug, String label, Widget child})>[];

    if (_isAdmin) {
      tabs.add((
        slug: 'oversikt',
        label: 'Oversikt',
        child: TimeClockPresenceTab(profile: p),
      ));
      tabs.add((
        slug: 'timeliste',
        label: 'Timeliste',
        child: TimeClockTimesheetTab(profile: p, canEditAll: _canEditAll),
      ));
    }

    if (_mobileAllowed || p.access.can(AccessKeys.stemplingMobile)) {
      tabs.add((
        slug: 'min-dag',
        label: 'Min dag',
        child: TimeClockMobileTab(profile: p),
      ));
    }

    if (_canSettings) {
      tabs.add((
        slug: 'innstillinger',
        label: 'Innstillinger',
        child: TimeClockSettingsTab(profile: p),
      ));
    }

    if (tabs.isEmpty) {
      tabs.add((
        slug: 'info',
        label: 'Stempling',
        child: _KioskOnlyInfo(profile: p),
      ));
    }

    return tabs;
  }

  int _indexForSlug(String? slug, int count) {
    if (slug == null || slug.isEmpty || count == 0) return 0;
    final tabs = _buildTabDefs();
    final i = tabs.indexWhere((t) => t.slug == slug);
    return i >= 0 ? i.clamp(0, count - 1) : 0;
  }

  void _onTabChanged() {
    if (_tabController == null || _tabController!.indexIsChanging) return;
    final tabs = _buildTabDefs();
    RouteUrlSync.syncTab(
      context,
      basePath: AppPaths.stempling,
      index: _tabController!.index,
      slugs: tabs.map((t) => t.slug).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null || _tabController == null) {
      return const DriftProLoadingPage();
    }

    final tabs = _buildTabDefs();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.stempling,
      child: MobileShellScaffold(
        title: 'Stempling',
        bottom: TabBar(
          controller: _tabController,
          isScrollable: tabs.length > 3,
          tabs: tabs.map((t) => Tab(text: t.label)).toList(),
        ),
        backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
        body: TabBarView(
          controller: _tabController,
          children: tabs.map((t) => t.child).toList(),
        ),
      ),
    );
  }
}

class _KioskOnlyInfo extends StatelessWidget {
  const _KioskOnlyInfo({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tablet_mac, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Stempl via kiosk',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Du har ikke mobiltilgang. Bruk stemplingsterminalen på jobb '
              'med ansattnummer og PIN-kode.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
