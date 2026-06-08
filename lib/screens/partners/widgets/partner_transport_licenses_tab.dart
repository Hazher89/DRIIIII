import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Flere transportløyver per bedrift — egen mappe/seksjon.
class PartnerTransportLicensesTab extends StatefulWidget {
  final Partner partner;
  final Future<void> Function() onChanged;

  const PartnerTransportLicensesTab({
    super.key,
    required this.partner,
    required this.onChanged,
  });

  @override
  State<PartnerTransportLicensesTab> createState() => _PartnerTransportLicensesTabState();
}

class _PartnerTransportLicensesTabState extends State<PartnerTransportLicensesTab> {
  List<PartnerTransportLicense> _licenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PartnerService.fetchTransportLicenses(widget.partner.id);
    if (mounted) {
      setState(() {
        _licenses = list;
        _loading = false;
      });
    }
  }

  Future<void> _addLicense() async {
    final numberCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final issuerCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime? validFrom;
    DateTime? validTo;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Registrer transportløyve'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Løyvenummer *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Reg.nr / kjøretøy (valgfritt)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: issuerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Utstedende myndighet',
                    border: OutlineInputBorder(),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gyldig fra'),
                  subtitle: Text(validFrom != null ? DateFormat('dd.MM.yyyy').format(validFrom!) : '—'),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: validFrom ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setSt(() => validFrom = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gyldig til'),
                  subtitle: Text(validTo != null ? DateFormat('dd.MM.yyyy').format(validTo!) : '—'),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: validTo ?? DateTime.now().add(const Duration(days: 365)),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setSt(() => validTo = d);
                  },
                ),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notater', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, numberCtrl.text.trim().isNotEmpty),
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      numberCtrl.dispose();
      plateCtrl.dispose();
      issuerCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    try {
      await PartnerService.addTransportLicense(
        PartnerTransportLicense(
          id: '',
          partnerId: widget.partner.id,
          companyId: widget.partner.companyId,
          licenseNumber: numberCtrl.text.trim(),
          vehiclePlate: plateCtrl.text.trim().isEmpty ? null : plateCtrl.text.trim().toUpperCase(),
          validFrom: validFrom,
          validTo: validTo,
          issuer: issuerCtrl.text.trim().isEmpty ? null : issuerCtrl.text.trim(),
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          createdAt: DateTime.now(),
        ),
      );
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      numberCtrl.dispose();
      plateCtrl.dispose();
      issuerCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }

    final expired = _licenses.where((l) => l.isExpired).length;
    final soon = _licenses.where((l) => l.expiresSoon).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          PartnerHeroBanner(
            compact: true,
            title: 'Transportløyver',
            subtitle: 'Registrer alle løyver for bedriften — gyldighet og sporbarhet.',
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.verified_outlined, color: Colors.white),
            ),
          ),
          PartnerKpiStrip(
            items: [
              PartnerKpiItem(
                label: 'Løyver',
                value: '${_licenses.length}',
                color: DriftProTheme.primaryGreen,
                icon: Icons.verified_outlined,
              ),
              PartnerKpiItem(
                label: 'Utløper snart',
                value: '$soon',
                color: DriftProTheme.warning,
                icon: Icons.schedule,
              ),
              PartnerKpiItem(
                label: 'Utløpt',
                value: '$expired',
                color: DriftProTheme.error,
                icon: Icons.error_outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _addLicense,
              icon: const Icon(Icons.add),
              label: const Text('Nytt løyve'),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            ),
          ),
          const SizedBox(height: 12),
          if (_licenses.isEmpty)
            PartnerEmptyState(
              icon: Icons.assignment_outlined,
              title: 'Ingen transportløyver',
              subtitle: 'Legg til ett eller flere løyver med nummer og gyldighetsperiode.',
              action: OutlinedButton.icon(
                onPressed: _addLicense,
                icon: const Icon(Icons.add),
                label: const Text('Registrer løyve'),
              ),
            )
          else
            ..._licenses.map(_licenseCard),
        ],
      ),
    );
  }

  Widget _licenseCard(PartnerTransportLicense lic) {
    Color accent = DriftProTheme.primaryGreen;
    if (lic.isExpired) {
      accent = DriftProTheme.error;
    } else if (lic.expiresSoon) {
      accent = DriftProTheme.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: ListTile(
        leading: Icon(Icons.verified_user_outlined, color: accent),
        title: Text(lic.licenseNumber, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lic.vehiclePlate != null) Text('Kjøretøy: ${lic.vehiclePlate}'),
            Text(
              'Gyldig: ${lic.validFrom != null ? DateFormat('dd.MM.yyyy').format(lic.validFrom!) : "—"}'
              ' → ${lic.validTo != null ? DateFormat('dd.MM.yyyy').format(lic.validTo!) : "—"}',
            ),
            if (lic.issuer != null) Text('Utstedt av: ${lic.issuer}'),
            if (lic.notes != null) Text(lic.notes!, style: DriftProTheme.caption),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () async {
            await PartnerService.deleteTransportLicense(lic.id, widget.partner.id);
            await _load();
            await widget.onChanged();
          },
        ),
      ),
    );
  }
}
