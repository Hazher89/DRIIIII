import 'package:flutter/material.dart';

import '../../../core/services/brreg_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_modern_ui.dart';
import 'partner_ui.dart';

/// Delte, kompakte UI-komponenter for bedriftsliste og registrering.
class PartnerCompaniesUi {
  PartnerCompaniesUi._();

  static Future<void> showRegisterHub(
    BuildContext context, {
    required VoidCallback onSingle,
    required VoidCallback onBulkBrreg,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PartnerUi.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DriftProTheme.radiusLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Registrer bedrift', style: DriftProTheme.headingSm),
              const SizedBox(height: 4),
              Text(
                'Én bedrift med MAVI og sjåfør, eller masseimport fra Brreg.',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 16),
              _RegisterOptionCard(
                icon: Icons.storefront_outlined,
                title: 'Én bedrift',
                subtitle: 'Brreg → kontakt → MAVI & sjåfør',
                onTap: () {
                  Navigator.pop(ctx);
                  onSingle();
                },
              ),
              const SizedBox(height: 10),
              _RegisterOptionCard(
                icon: Icons.cloud_download_outlined,
                title: 'Flere fra Brreg',
                subtitle: 'Lim inn org.nr eller navn',
                onTap: () {
                  Navigator.pop(ctx);
                  onBulkBrreg();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<List<String>> showMaviBulkPasteDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lim inn MAVI-nummer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Én per linje, eller kommaseparert. Eksempel: M0001, NO_O_M0002',
              style: DriftProTheme.caption,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 8,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'M0001\nM0002',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            child: const Text('Legg til'),
          ),
        ],
      ),
    );
    if (ok != true) return [];
    return MaviUnitCodes.parseBulk(ctrl.text);
  }
}

class _RegisterOptionCard extends StatelessWidget {
  const _RegisterOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2D3748)
        : const Color(0xFFE5E7EB);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kompakt KPI-rad (én linje, ikke horisontal scroll).
class PartnerDenseKpiRow extends StatelessWidget {
  const PartnerDenseKpiRow({super.key, required this.items});

  final List<PartnerKpiItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _DenseKpiCell(item: items[i])),
          ],
        ],
      ),
    );
  }
}

class _DenseKpiCell extends StatelessWidget {
  const _DenseKpiCell({required this.item});

  final PartnerKpiItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: item.color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            item.value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: item.color, height: 1),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: PartnerUi.mutedText(context)),
          ),
        ],
      ),
    );
  }
}

/// Kompakt bedriftskort — mye info, lav høyde.
class PartnerCompanyCompactTile extends StatelessWidget {
  const PartnerCompanyCompactTile({
    super.key,
    required this.partner,
    required this.vehicles,
    this.matchReasons = const [],
    required this.onTap,
  });

  final Partner partner;
  final List<PartnerVehicle> vehicles;
  final List<String> matchReasons;
  final VoidCallback onTap;

  List<PartnerVehicle> get _maviVehicles => vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .toList();

  @override
  Widget build(BuildContext context) {
    final maviVehicles = PartnerMaviVehicleOverview.filterMavi(_maviVehicles);
    final active = partner.isActive != false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? Colors.grey.withValues(alpha: 0.14)
                    : Colors.red.withValues(alpha: 0.35),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _Avatar(name: partner.name, active: active),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              partner.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                          if (!active)
                            const PartnerStatusBadge(
                              label: 'Inaktiv',
                              color: Colors.red,
                              icon: Icons.pause_circle_outline,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (partner.orgNumber != null) partner.orgNumber!,
                          if (partner.ownerName != null && partner.ownerName!.isNotEmpty) partner.ownerName!,
                          if (partner.phone != null && partner.phone!.isNotEmpty) partner.phone!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: PartnerUi.mutedText(context)),
                      ),
                      const SizedBox(height: 4),
                      PartnerMaviVehicleOverview(
                        vehicles: PartnerMaviVehicleOverview.filterMavi(_maviVehicles),
                        dense: true,
                      ),
                      if (partner.notes != null && partner.notes!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          partner.notes!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                      if (matchReasons.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            matchReasons.take(2).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9, color: Colors.amber.shade800),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${maviVehicles.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: maviVehicles.isEmpty ? Colors.grey : DriftProTheme.primaryGreen,
                      ),
                    ),
                    Text('MAVI', style: TextStyle(fontSize: 9, color: PartnerUi.mutedText(context))),
                    Icon(Icons.chevron_right, size: 18, color: PartnerUi.mutedText(context)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.active});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: active ? DriftProTheme.primaryGradient : null,
        color: active ? null : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
      ),
    );
  }
}

class PartnerMaviChipRow extends StatelessWidget {
  const PartnerMaviChipRow({super.key, required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) {
      return Text(
        'Ingen MAVI — trykk for å legge til',
        style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
      );
    }
    final show = codes.length > 5 ? codes.take(4).toList() : codes;
    final extra = codes.length - show.length;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        ...show.map(
          (c) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.25)),
            ),
            child: Text(
              c,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: DriftProTheme.primaryGreenDark,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        if (extra > 0)
          Text('+$extra', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: PartnerUi.mutedText(context))),
      ],
    );
  }
}

/// Steg-indikator for registreringsveiviser.
class PartnerWizardStepper extends StatelessWidget {
  const PartnerWizardStepper({
    super.key,
    required this.labels,
    required this.current,
  });

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final done = i < current;
          final active = i == current;
          final color = done || active ? DriftProTheme.primaryGreen : Colors.grey.shade400;
          return Expanded(
            child: Row(
              children: [
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i <= current ? DriftProTheme.primaryGreen : Colors.grey.shade300,
                    ),
                  ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: color,
                      child: done
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: active ? Colors.white : Colors.grey.shade700,
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        color: active ? DriftProTheme.primaryGreenDark : PartnerUi.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Brreg-oppslag (gjenbrukbar).
class PartnerBrregLookupPanel extends StatefulWidget {
  const PartnerBrregLookupPanel({
    super.key,
    required this.onApply,
  });

  final void Function(BrregCompanyDetails details) onApply;

  @override
  State<PartnerBrregLookupPanel> createState() => _PartnerBrregLookupPanelState();
}

class _PartnerBrregLookupPanelState extends State<PartnerBrregLookupPanel> {
  final _nameSearch = TextEditingController();
  final _orgCtrl = TextEditingController();
  bool _loading = false;
  List<BrregCompanyHit> _hits = [];

  @override
  void dispose() {
    _nameSearch.dispose();
    _orgCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchName() async {
    setState(() => _loading = true);
    try {
      final hits = await BrregService.searchByName(_nameSearch.text);
      setState(() => _hits = hits);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _lookupOrg() async {
    setState(() => _loading = true);
    try {
      final d = await BrregService.fetchByOrgNumber(_orgCtrl.text);
      if (d == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fant ingen enhet.')));
        }
        return;
      }
      widget.onApply(d);
      setState(() => _hits = []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pickHit(BrregCompanyHit h) {
    _orgCtrl.text = h.orgNumber;
    _lookupOrg();
  }

  @override
  Widget build(BuildContext context) {
    return PartnerSectionCard(
      icon: Icons.account_balance_outlined,
      iconColor: DriftProTheme.accentBlue,
      title: 'Brønnøysund (Brreg)',
      subtitle: 'Søk navn eller skriv org.nr — data fylles automatisk',
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameSearch,
                decoration: const InputDecoration(
                  labelText: 'Søk bedriftsnavn',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _searchName(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _loading ? null : _searchName,
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.accentBlue),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 20),
            ),
          ],
        ),
        if (_hits.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._hits.take(6).map(
            (h) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              subtitle: Text('${h.orgNumber} · ${h.city ?? ''}', style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.download_outlined, size: 18),
              onTap: () => _pickHit(h),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _orgCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Org.nr (9 siffer)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _loading ? null : _lookupOrg,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('Hent'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sammenleggbar seksjon (oversikt / redigering).
class PartnerExpandableSection extends StatefulWidget {
  const PartnerExpandableSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.badge,
    this.initiallyExpanded = false,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? badge;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<PartnerExpandableSection> createState() => _PartnerExpandableSectionState();
}

class _PartnerExpandableSectionState extends State<PartnerExpandableSection> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.iconColor ?? DriftProTheme.primaryGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: accent),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        if (widget.subtitle != null)
                          Text(widget.subtitle!, style: DriftProTheme.caption.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                  if (widget.badge != null) ...[widget.badge!, const SizedBox(width: 8)],
                  Icon(_open ? Icons.expand_less : Icons.expand_more, color: PartnerUi.mutedText(context)),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
            ),
        ],
      ),
    );
  }
}

/// Kompakt MAVI-rad for registrering.
class PartnerMaviRegisterCard extends StatelessWidget {
  const PartnerMaviRegisterCard({
    super.key,
    required this.index,
    required this.maviController,
    required this.driverNameController,
    required this.driverPhoneController,
    required this.usernamePreview,
    required this.onRemove,
  });

  final int index;
  final TextEditingController maviController;
  final TextEditingController driverNameController;
  final TextEditingController driverPhoneController;
  final String usernamePreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${index + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 20, color: Colors.red),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: maviController,
                  decoration: const InputDecoration(
                    labelText: 'MAVI *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: driverNameController,
                  decoration: const InputDecoration(
                    labelText: 'Sjåfør',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: driverPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefon (SMS innlogging)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (usernamePreview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Bruker: $usernamePreview',
                style: TextStyle(fontSize: 10, color: PartnerUi.mutedText(context), fontFamily: 'monospace'),
              ),
            ),
        ],
      ),
    );
  }
}
