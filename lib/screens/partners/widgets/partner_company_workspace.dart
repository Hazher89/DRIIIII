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
  List<PartnerPortalAccount> _portalAccounts = [];
  UserProfile? _profile;
  List<PartnerDetailTabDef> _tabs = [];
  TabController? _tabCtrl;
  bool _loading = true;
  bool _showAllSections = false;

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
    final portalAccounts = await PartnerService.fetchPortalAccounts(_p.id);
    if (fresh != null && mounted) {
      setState(() {
        _p = fresh;
        _vehicles = vehicles;
        _portalAccounts = portalAccounts;
      });
      widget.onDataChanged();
    }
  }

  int get _maviCount => _vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .length;
  int get _ownerCount => _portalAccounts.where((a) => a.isOwner && a.isActive).length;
  int get _driverCount => _portalAccounts.where((a) => a.isDriver && a.isActive).length;
  Set<String> get _smsPhones {
    final out = <String>{};
    void addPhone(String? p) {
      if (p == null) return;
      final v = p.trim();
      if (v.isNotEmpty) out.add(v);
    }

    addPhone(_p.phone);
    for (final a in _portalAccounts.where((a) => a.isActive)) {
      addPhone(a.phone);
    }
    for (final v in _vehicles.where((v) => v.isActive)) {
      addPhone(v.phone);
    }
    return out;
  }
  bool get _needsOwnerAccount => _ownerCount == 0;
  bool get _needsSmsPhone => _smsPhones.isEmpty;
  bool get _hasNoMavi => _maviCount == 0;

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
        _smartStatusStrip(context),
        if (_tabCtrl != null)
          _sectionsToolbar(context),
        if (_tabCtrl != null && _showAllSections)
          Material(
            color: PartnerModernUi.surface(context),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerHeight: 1,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              tabs: _tabs.map((t) => Tab(icon: Icon(t.icon, size: 18), text: t.label)).toList(),
            ),
          ),
        Expanded(
          child: _tabCtrl == null
              ? const Center(child: Text('Ingen tilgang til detaljer'))
              : TabBarView(
                  controller: _tabCtrl,
                  children: _tabs.map(_tabChild).toList(),
                ),
        ),
      ],
    );
  }

  Widget _sectionsToolbar(BuildContext context) {
    final ctrl = _tabCtrl!;
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final tab = _tabs[ctrl.index];
        final quick = _preferredQuickTabs();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PartnerSmartSectionPicker(
              title: 'Viser',
              currentLabel: tab.label,
              onPick: _openSectionPicker,
              onToggleAll: () => setState(() => _showAllSections = !_showAllSections),
              showAll: _showAllSections,
            ),
            if (quick.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: quick.map((t) {
                    final i = _tabs.indexOf(t);
                    final selected = ctrl.index == i;
                    return ChoiceChip(
                      label: Text(t.label, style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      onSelected: (_) => ctrl.animateTo(i),
                      avatar: Icon(t.icon, size: 14),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _smartStatusStrip(BuildContext context) {
    final issues = <String>[
      if (_needsOwnerAccount) 'Mangler bedriftsansvarlig-konto',
      if (_needsSmsPhone) 'Ingen SMS-nummer',
      if (_hasNoMavi) 'Ingen MAVI registrert',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        border: Border.all(color: PartnerModernUi.border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                issues.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
                size: 16,
                color: issues.isEmpty ? const Color(0xFF15803D) : const Color(0xFFD97706),
              ),
              const SizedBox(width: 6),
              Text(
                issues.isEmpty ? 'Datakvalitet: God' : 'Datakvalitet: Trenger oppfølging',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: PartnerModernUi.textPrimary(context),
                ),
              ),
              const Spacer(),
              Text(
                '${_smsPhones.length} SMS-nummer',
                style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _kpiChip(context, 'Bedriftsansvarlig', '$_ownerCount'),
              _kpiChip(context, 'Sjåfører', '$_driverCount'),
              _kpiChip(context, 'MAVI', '$_maviCount'),
              _kpiChip(context, 'Reg.nr', '${_vehicles.length - _maviCount}'),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: issues
                  .map(
                    (i) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(i, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiChip(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: PartnerModernUi.textPrimary(context),
        ),
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
