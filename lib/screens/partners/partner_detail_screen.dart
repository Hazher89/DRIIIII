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
  List<PartnerPortalAccount> _portalAccounts = const [];
  UserProfile? _profile;
  List<PartnerDetailTabDef> _visibleTabs = const [];
  bool _accessLoading = true;
  bool _showAllSections = false;

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
    final portalAccounts = await PartnerService.fetchPortalAccounts(_p.id);
    if (fresh != null && mounted) {
      setState(() {
        _p = fresh;
        _vehicles = vehicles;
        _portalAccounts = portalAccounts;
      });
    }
  }

  Future<void> _confirmDelete() async {
    if (_profile?.access.canPartnersDelete != true &&
        _profile?.access.canPartnersAdmin != true) {
      return;
    }
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Slett samarbeidspartner permanent?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dette sletter «${_p.name}» permanent fra Supabase og systemet.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Alt knyttet til bedriften fjernes: ruter, dokumenter, portaltilganger, kjøretøy, bilutleie og historikk.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(
                  labelText: 'Skriv SLETT for å bekrefte',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDlg(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: confirmCtrl.text.trim().toUpperCase() == 'SLETT'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Slett permanent'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
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
  int get _ownerCount => _portalAccounts.where((a) => a.isOwner && a.isActive).length;
  int get _driverCount => _portalAccounts.where((a) => a.isDriver && a.isActive).length;

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

  Future<void> _openSectionPicker() async {
    final ctrl = _tabs;
    if (ctrl == null || _visibleTabs.isEmpty) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _visibleTabs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final tab = _visibleTabs[i];
            final active = ctrl.index == i;
            return ListTile(
              leading: Icon(tab.icon),
              title: Text(tab.label),
              trailing: active ? const Icon(Icons.check_circle, color: Colors.green) : null,
              onTap: () => Navigator.of(ctx).pop(i),
            );
          },
        ),
      ),
    );
    if (selected != null && mounted && _tabs != null) {
      _tabs!.animateTo(selected);
    }
  }

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
          PartnerSmartActionsPanel(
            title: 'Smart status',
            actions: [
              PartnerSmartAction(
                label: 'Registrerte kontoer: $_ownerCount bedriftsansvarlige · $_driverCount sjåfører',
                icon: Icons.badge_outlined,
              ),
              PartnerSmartAction(
                label: _p.routesOwnerOnly
                    ? 'Rute-SMS: kun bedriftsansvarlig'
                    : 'Rute-SMS: bedriftsansvarlig + sjåfør',
                icon: _p.routesOwnerOnly ? Icons.person_outline : Icons.groups_2_outlined,
              ),
              if (_ownerCount == 0)
                const PartnerSmartAction(
                  label: 'Mangler bedriftsansvarlig-konto',
                  hint: 'Opprett portal for bedriftsansvarlig i oversikt-fanen',
                  icon: Icons.warning_amber_rounded,
                ),
            ],
          ),
          if (_tabs != null)
            _smartToolbar(),
          if (_tabs != null && _showAllSections)
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

  Widget _smartToolbar() {
    final ctrl = _tabs!;
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final tab = _visibleTabs[ctrl.index];
        return PartnerSmartSectionPicker(
          title: 'Viser',
          currentLabel: tab.label,
          onPick: _openSectionPicker,
          onToggleAll: () => setState(() => _showAllSections = !_showAllSections),
          showAll: _showAllSections,
        );
      },
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

  Future<void> _uploadFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    if (!mounted) return;
    final title = TextEditingController(text: 'Oppsummering');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Last opp oppsummering (PDF/filer)'),
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

    final baseTitle = title.text.trim().isEmpty ? 'Oppsummering' : title.text.trim();
    title.dispose();

    var uploadedCount = 0;
    for (var i = 0; i < picked.files.length; i++) {
      final file = picked.files[i];
      final bytes = file.bytes ??
          (file.path != null && !kIsWeb ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) continue;

      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath =
          'company_${widget.partner.companyId}/partner_summaries/${widget.partner.id}/${DateTime.now().millisecondsSinceEpoch}_${i}_$safeName';

      final ext = file.name.split('.').length > 1 ? file.name.split('.').last.toLowerCase() : '';
      final mime = (ext == 'pdf'
          ? 'application/pdf'
          : ext == 'png'
              ? 'image/png'
              : ext == 'jpg' || ext == 'jpeg'
                  ? 'image/jpeg'
                  : ext == 'txt'
                      ? 'text/plain'
                      : ext == 'doc'
                          ? 'application/msword'
                          : ext == 'docx'
                              ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                              : ext == 'xls'
                                  ? 'application/vnd.ms-excel'
                                  : ext == 'xlsx'
                                      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                                      : null);

      try {
        final storedPath = (mime == 'application/pdf' || ext == 'pdf')
            ? await PartnerService.uploadPartnerDocumentPdf(storagePath: storagePath, bytes: bytes)
            : await PartnerService.uploadPartnerDocumentFile(
                storagePath: storagePath,
                bytes: bytes,
                mimeType: mime,
              );

        await PartnerService.addDocument(
          PartnerDocument(
            id: '',
            partnerId: widget.partner.id,
            companyId: widget.partner.companyId,
            title: picked.files.length > 1 ? '$baseTitle — ${i + 1}' : baseTitle,
            storagePath: storedPath,
            fileName: file.name,
            mimeType: mime,
            docCategory: 'summary',
            createdAt: DateTime.now(),
          ),
        );
        uploadedCount++;
      } catch (_) {
        // Fortsetter med neste fil
      }
    }

    await _load();
    await widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadedCount > 0
                ? 'Lastet opp $uploadedCount fil(er) til oppsummering.'
                : 'Ingen filer ble lastet opp (feil eller tom fil).',
          ),
        ),
      );
    }
  }

  Future<void> _open(PartnerDocument d) async {
    final p = d.storagePath;
    if (p == null || p.isEmpty) return;
    try {
      final url = await PartnerService.resolveStorageUrl(p);
      final mime = d.mimeType ?? '';
      final extParts = (d.fileName ?? '').split('.');
      final ext = extParts.length > 1 ? extParts.last.toLowerCase() : null;
      final isImage = mime.startsWith('image/') || (ext == 'png' || ext == 'jpg' || ext == 'jpeg');

      if (isImage) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
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
            'Oppsummering (PDF/filer) er kun synlig internt og for denne samarbeidspartneren (dataminimering).',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _uploadFiles,
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Last opp oppsummering (PDF/filer)'),
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
                    final mime = d.mimeType ?? '';
                    final extParts = (d.fileName ?? '').split('.');
                    final ext = extParts.length > 1 ? extParts.last.toLowerCase() : null;
                    final isPdf = mime == 'application/pdf' || ext == 'pdf';
                    final isImg = mime.startsWith('image/') || (ext == 'png' || ext == 'jpg' || ext == 'jpeg');
                    return Card(
                      child: ListTile(
                        leading: isImg
                            ? const Icon(Icons.image_outlined)
                            : isPdf
                                ? const Icon(Icons.picture_as_pdf_outlined)
                                : const Icon(Icons.insert_drive_file_outlined),
                        title: Text(d.title),
                        subtitle: Text('${d.fileName ?? d.storagePath ?? ''}\n${mime.isNotEmpty ? mime : '—'}'),
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
