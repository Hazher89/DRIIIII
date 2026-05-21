import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/permissions/access_keys.dart';
import '../../core/permissions/partner_access.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../models/user_profile.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import 'widgets/partner_assigned_routes_tab.dart';
import 'widgets/partner_compliance_tab.dart';
import 'widgets/partner_documents_tab.dart';
import 'widgets/partner_fri_tab.dart';
import 'widgets/partner_overview_tab.dart';
import 'widgets/partner_transport_licenses_tab.dart';
import 'widgets/partner_modern_ui.dart';
import 'widgets/partner_ui.dart';
import 'widgets/partner_vehicle_inspection_tab.dart';

class PartnerDetailScreen extends StatefulWidget {
  final Partner partner;
  const PartnerDetailScreen({super.key, required this.partner});

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> with SingleTickerProviderStateMixin {
  TabController? _tabs;
  late Partner _p;
  List<PartnerVehicle> _vehicles = const [];
  UserProfile? _profile;
  List<PartnerDetailTabDef> _visibleTabs = const [];
  bool _accessLoading = true;

  @override
  void initState() {
    super.initState();
    _p = widget.partner;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    final tabs = PartnerAccess.visibleDetailTabs(profile?.access);
    if (!mounted) return;
    _tabs?.dispose();
    setState(() {
      _profile = profile;
      _visibleTabs = tabs;
      _accessLoading = false;
      if (tabs.isNotEmpty) {
        _tabs = TabController(length: tabs.length, vsync: this);
      }
    });
    await _reload();
  }

  @override
  void dispose() {
    _tabs?.dispose();
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
    }
  }

  Future<void> _confirmDelete() async {
    if (_profile?.access.canPartnersDelete != true &&
        _profile?.access.canPartnersAdmin != true) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett samarbeidspartner?'),
        content: Text(
          '«${_p.name}» og alle tilknyttede data (biler, ruter, dokumenter) '
          'fjernes permanent fra systemet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await PartnerService.deletePartner(_p.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partner slettet')),
      );
      Navigator.pop(context, true);
    }
  }

  int get _maviCount => _vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .length;

  int get _regCount => _vehicles.length - _maviCount;

  Widget _buildTabBody(PartnerDetailTabDef tab) {
    final child = switch (tab.accessKey) {
      AccessKeys.partnersTabOversikt =>
        PartnerOverviewTab(partner: _p, vehicles: _vehicles, onSaved: _reload),
      AccessKeys.partnersTabBilkontroll =>
        PartnerVehicleInspectionTab(partner: _p, vehicles: _vehicles),
      AccessKeys.partnersTabRuter => PartnerAssignedRoutesTab(partner: _p),
      AccessKeys.partnersTabDokumenter =>
        PartnerDocumentsTab(partner: _p, onChanged: _reload),
      AccessKeys.partnersTabLoyver =>
        PartnerTransportLicensesTab(partner: _p, onChanged: _reload),
      AccessKeys.partnersTabOppfolging =>
        PartnerComplianceTab(partner: _p, onChanged: _reload),
      AccessKeys.partnersTabOppsummering =>
        _SummaryTab(partner: _p, onChanged: _reload),
      AccessKeys.partnersTabFri => PartnerFriTab(partner: _p, vehicles: _vehicles),
      _ => const SizedBox.shrink(),
    };
    return PermissionGuard(
      profile: _profile,
      accessKey: tab.accessKey,
      child: child,
    );
  }

  List<(IconData, String)> get _tabBarEntries =>
      _visibleTabs.map((t) => (t.icon, t.label)).toList();

  @override
  Widget build(BuildContext context) {
    if (_accessLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!PartnerAccess.canOpenPartnerDetail(_profile?.access)) {
      return PermissionGuard(
        profile: _profile,
        accessKey: AccessKeys.partnersTabOversikt,
        deniedMessage: 'Du har ikke tilgang til denne samarbeidspartneren.',
        child: const SizedBox.shrink(),
      );
    }

    final loc = [_p.city, _p.postalCode]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? DriftProTheme.surfaceDark
          : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(_p.name, style: DriftProTheme.headingSm),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
          if (_profile?.access.canPartnersDelete == true ||
              _profile?.access.canPartnersAdmin == true)
            IconButton(
              tooltip: 'Slett partner',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PartnerModernDetailHeader(
            title: _p.tradeName?.isNotEmpty == true ? _p.tradeName! : _p.name,
            subtitle: [
              if (_p.orgNumber != null) 'Org.nr ${_p.orgNumber}',
              if (_p.ownerName != null && _p.ownerName!.isNotEmpty) _p.ownerName!,
              if (loc.isNotEmpty) loc,
            ].join(' · '),
            maviCount: _maviCount,
            regCount: _regCount,
            isActive: _p.isActive,
            canToggleActive: _profile?.access.canPartnersAdmin == true ||
                _profile?.access.canPartnersCreate == true,
            onActiveChanged: (_profile?.access.canPartnersAdmin == true ||
                    _profile?.access.canPartnersCreate == true)
                ? (v) async {
                    await PartnerService.setPartnerActive(partnerId: _p.id, isActive: v);
                    await _reload();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            v
                                ? 'Bedriften er aktiv i ruteplanlegger'
                                : 'Bedriften er deaktivert',
                          ),
                        ),
                      );
                    }
                  }
                : null,
          ),
          if (_tabs != null)
            PartnerDetailTabBar(controller: _tabs!, tabs: _tabBarEntries),
          Expanded(
            child: _tabs == null
                ? const SizedBox.shrink()
                : TabBarView(
                    controller: _tabs,
                    children: _visibleTabs.map(_buildTabBody).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}


/// Oppsummerings-PDF: egen kategori (doc_category=summary). RLS: kun MAVI i selskapet + denne partneren.
class _SummaryTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;
  const _SummaryTab({required this.partner, required this.onChanged});

  @override
  State<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<_SummaryTab> {
  List<PartnerDocument> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await PartnerService.fetchDocuments(
      widget.partner.id,
      docCategories: const ['summary'],
    );
    if (mounted) setState(() => _list = d);
  }

  Future<void> _uploadPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes ??
        (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke lese PDF-fil.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final title = TextEditingController(text: 'Oppsummering');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last opp oppsummering (PDF)'),
        content: TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: 'Tittel',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Last opp')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'company_${widget.partner.companyId}/partner_summaries/${widget.partner.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    try {
      await PartnerService.uploadPartnerDocumentPdf(storagePath: storagePath, bytes: bytes);
      await PartnerService.addDocument(
        PartnerDocument(
          id: '',
          partnerId: widget.partner.id,
          companyId: widget.partner.companyId,
          title: title.text.trim().isEmpty ? 'Oppsummering' : title.text.trim(),
          storagePath: storagePath,
          fileName: file.name,
          mimeType: 'application/pdf',
          docCategory: 'summary',
          createdAt: DateTime.now(),
        ),
      );
      await _load();
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oppsummering er delt med partner (kun deres tilgang).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opplasting feilet: $e')));
      }
    } finally {
      title.dispose();
    }
  }

  Future<void> _open(PartnerDocument d) async {
    final p = d.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.getDocumentPdfSignedUrl(p);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke åpne: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Oppsummerings-PDF er kun synlig for dere internt og for denne samarbeidspartneren (dataminimering).',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _uploadPdf,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Last opp oppsummering-PDF'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? const Center(child: Text('Ingen oppsummering delt ennå.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final d = _list[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(d.title),
                        subtitle: Text(d.fileName ?? d.storagePath ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _open(d),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
