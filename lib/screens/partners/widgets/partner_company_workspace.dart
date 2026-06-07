import 'package:flutter/material.dart';

import '../../../core/permissions/access_keys.dart';
import '../../../core/permissions/partner_access.dart';
import '../../../core/permissions/permission_gate.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../partner_detail_screen.dart';
import 'partner_assigned_routes_tab.dart';
import 'partner_compliance_tab.dart';
import 'partner_documents_tab.dart';
import 'partner_fri_tab.dart';
import 'partner_modern_ui.dart';
import 'partner_overview_tab.dart';
import 'partner_transport_licenses_tab.dart';
import 'partner_vehicle_inspection_tab.dart';

/// Åpner arbeidsflate for én bedrift — panel eller full skjerm.
class PartnerCompanyWorkspace {
  PartnerCompanyWorkspace._();

  static Future<bool?> open(
    BuildContext context, {
    required Partner partner,
    required VoidCallback onDataChanged,
  }) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      return Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PartnerCompanyWorkspacePage(
            partner: partner,
            onDataChanged: onDataChanged,
          ),
        ),
      );
    }
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: PartnerModernUi.surface(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: PartnerModernUi.border(ctx)),
          ),
          child: PartnerCompanyWorkspaceBody(
            partner: partner,
            scrollController: scrollController,
            onDataChanged: onDataChanged,
            onClose: (result) => Navigator.pop(ctx, result),
          ),
        ),
      ),
    );
  }
}

class PartnerCompanyWorkspacePage extends StatelessWidget {
  const PartnerCompanyWorkspacePage({
    super.key,
    required this.partner,
    required this.onDataChanged,
  });

  final Partner partner;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F1419)
          : const Color(0xFFF3F4F6),
      body: PartnerCompanyWorkspaceBody(
        partner: partner,
        onDataChanged: onDataChanged,
        onClose: (r) => Navigator.pop(context, r),
      ),
    );
  }
}

class PartnerCompanyWorkspaceBody extends StatefulWidget {
  const PartnerCompanyWorkspaceBody({
    super.key,
    required this.partner,
    required this.onDataChanged,
    required this.onClose,
    this.scrollController,
  });

  final Partner partner;
  final VoidCallback onDataChanged;
  final void Function(bool? result) onClose;
  final ScrollController? scrollController;

  @override
  State<PartnerCompanyWorkspaceBody> createState() => _PartnerCompanyWorkspaceBodyState();
}

class _PartnerCompanyWorkspaceBodyState extends State<PartnerCompanyWorkspaceBody>
    with SingleTickerProviderStateMixin {
  late Partner _p;
  List<PartnerVehicle> _vehicles = [];
  UserProfile? _profile;
  List<PartnerDetailTabDef> _tabs = [];
  TabController? _tabCtrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _p = widget.partner;
    _init();
  }

  @override
  void didUpdateWidget(covariant PartnerCompanyWorkspaceBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partner.id != widget.partner.id) {
      _p = widget.partner;
      _loading = true;
      _init();
    }
  }

  Future<void> _init() async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    final tabs = PartnerAccess.visibleDetailTabs(profile?.access);
    if (!mounted) return;
    final oldCtrl = _tabCtrl;
    oldCtrl?.dispose();
    final ctrl = tabs.isNotEmpty ? TabController(length: tabs.length, vsync: this) : null;
    setState(() {
      _profile = profile;
      _tabs = tabs;
      _tabCtrl = ctrl;
    });
    await _reload();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final fresh = await PartnerService.fetchPartner(_p.id);
    final vehicles = await PartnerService.fetchVehicles(_p.id);
    if (fresh != null && mounted) {
      setState(() {
        _p = fresh;
        _vehicles = vehicles;
      });
      widget.onDataChanged();
    }
  }

  int get _maviCount => _vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .length;
  Future<void> _openFullScreen() async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PartnerDetailScreen(partner: _p)),
    );
    if (deleted == true) {
      widget.onClose(true);
    } else {
      await _reload();
    }
  }

  Future<void> _openSectionPicker() async {
    final ctrl = _tabCtrl;
    if (ctrl == null || _tabs.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _tabs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final tab = _tabs[i];
              final active = ctrl.index == i;
              return ListTile(
                leading: Icon(tab.icon),
                title: Text(tab.label),
                trailing: active ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () => Navigator.of(ctx).pop(i),
              );
            },
          ),
        );
      },
    );
    if (selected != null && mounted && _tabCtrl != null) {
      _tabCtrl!.animateTo(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Expanded(
          child: _tabCtrl == null
              ? const Center(child: Text('Ingen tilgang til detaljer'))
              : NestedScrollView(
                  controller: widget.scrollController,
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(
                      child: AnimatedBuilder(
                        animation: _tabCtrl!,
                        builder: (context, _) => _sectionPickerBar(context),
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabCtrl,
                    children: _tabs.map(_tabChild).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sectionPickerBar(BuildContext context) {
    final ctrl = _tabCtrl!;
    final tab = _tabs[ctrl.index];
    final shortcuts = _preferredQuickTabs()
        .where((t) => _tabs.indexOf(t) != ctrl.index)
        .take(2)
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Row(
        children: [
          Icon(tab.icon, size: 18, color: PartnerModernUi.textPrimary(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: PartnerModernUi.textPrimary(context),
              ),
            ),
          ),
          for (final shortcut in shortcuts) ...[
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: () => ctrl.animateTo(_tabs.indexOf(shortcut)),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              child: Text(shortcut.label),
            ),
          ],
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _openSectionPicker,
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: const Text('Bytt'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<PartnerDetailTabDef> _preferredQuickTabs() {
    final preferred = <String>[
      AccessKeys.partnersTabOversikt,
      AccessKeys.partnersTabRuter,
      AccessKeys.partnersTabDokumenter,
      AccessKeys.partnersTabBilkontroll,
    ];
    final ranked = <PartnerDetailTabDef>[];
    for (final key in preferred) {
      for (final tab in _tabs) {
        if (tab.accessKey == key) {
          ranked.add(tab);
          break;
        }
      }
    }
    for (final tab in _tabs) {
      if (!ranked.contains(tab)) ranked.add(tab);
    }
    return ranked.take(3).toList();
  }

  Widget _header(BuildContext context) {
    final loc = [_p.city, _p.postalCode].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: PartnerModernUi.border(context))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => widget.onClose(null),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: PartnerModernUi.textPrimary(context)),
                ),
                Text(
                  [
                    if (_p.orgNumber != null) _p.orgNumber!,
                    if (loc.isNotEmpty) loc,
                    '$_maviCount MAVI',
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Oppdater',
            icon: const Icon(Icons.refresh_outlined, size: 20),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: 'Full skjerm',
            icon: const Icon(Icons.open_in_full, size: 20),
            onPressed: _openFullScreen,
          ),
        ],
      ),
    );
  }

  Widget _tabChild(PartnerDetailTabDef tab) {
    Widget child;
    switch (tab.accessKey) {
      case AccessKeys.partnersTabOversikt:
        child = PartnerOverviewTab(partner: _p, vehicles: _vehicles, onSaved: _reload);
        break;
      case AccessKeys.partnersTabBilkontroll:
        child = PartnerVehicleInspectionTab(partner: _p, vehicles: _vehicles);
        break;
      case AccessKeys.partnersTabRuter:
        child = PartnerAssignedRoutesTab(partner: _p);
        break;
      case AccessKeys.partnersTabDokumenter:
        child = PartnerDocumentsTab(partner: _p, onChanged: _reload);
        break;
      case AccessKeys.partnersTabLoyver:
        child = PartnerTransportLicensesTab(partner: _p, onChanged: _reload);
        break;
      case AccessKeys.partnersTabOppfolging:
        child = PartnerComplianceTab(partner: _p, onChanged: _reload);
        break;
      case AccessKeys.partnersTabFri:
        child = PartnerFriTab(partner: _p, vehicles: _vehicles);
        break;
      default:
        child = const SizedBox.shrink();
    }
    return PermissionGuard(
      profile: _profile,
      accessKey: tab.accessKey,
      child: child,
    );
  }
}
