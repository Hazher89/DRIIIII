import 'package:flutter/material.dart';

import '../../core/services/brreg_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import 'widgets/partner_companies_ui.dart';
import 'widgets/partner_ui.dart';

class _BulkRow {
  _BulkRow({
    required this.sourceLine,
    this.details,
    this.error,
    this.warning,
  });

  final String sourceLine;
  final BrregCompanyDetails? details;
  final String? error;
  final String? warning;
  bool selected = true;
}

/// Masseimport av bedrifter fra Brreg — kompakt forhåndsvisning og registrering.
class BulkPartnersScreen extends StatefulWidget {
  const BulkPartnersScreen({super.key});

  @override
  State<BulkPartnersScreen> createState() => _BulkPartnersScreenState();
}

class _BulkPartnersScreenState extends State<BulkPartnersScreen> {
  final _pasteCtrl = TextEditingController();
  int _phase = 0; // 0 = lim inn, 1 = forhåndsvis
  bool _fetching = false;
  bool _saving = false;
  List<_BulkRow> _rows = [];

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  List<String> _splitLines(String raw) {
    return raw
        .split(RegExp(r'[\n,;\t]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _lookupBrreg() async {
    final lines = _splitLines(_pasteCtrl.text);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lim inn minst én linje med org.nr eller navn.')),
      );
      return;
    }
    setState(() {
      _fetching = true;
      _rows = [];
    });
    final out = <_BulkRow>[];
    for (final line in lines) {
      final digits = line.replaceAll(RegExp(r'\D'), '');
      try {
        if (digits.length == 9) {
          final d = await BrregService.fetchByOrgNumber(digits);
          out.add(_BulkRow(
            sourceLine: line,
            details: d,
            error: d == null ? 'Fant ikke i Brreg' : null,
          ));
        } else {
          final hits = await BrregService.searchByName(line);
          if (hits.isEmpty) {
            out.add(_BulkRow(sourceLine: line, error: 'Ingen treff'));
          } else {
            final d = await BrregService.fetchByOrgNumber(hits.first.orgNumber);
            out.add(_BulkRow(
              sourceLine: line,
              details: d,
              error: d == null ? 'Kunne ikke hente' : null,
              warning: hits.length > 1 ? 'Flere treff — valgte ${hits.first.name}' : null,
            ));
          }
        }
      } catch (e) {
        out.add(_BulkRow(sourceLine: line, error: '$e'));
      }
    }
    if (mounted) {
      setState(() {
        _rows = out;
        _fetching = false;
        _phase = 1;
      });
    }
  }

  Future<void> _registerSelected() async {
    final picked = _rows.where((r) => r.selected && r.details != null).toList();
    if (picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én gyldig bedrift.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Mangler company_id');
      var ok = 0;
      for (final row in picked) {
        final d = row.details!;
        await PartnerService.createPartner(
          Partner(
            id: '',
            companyId: cid,
            orgNumber: d.orgNumber,
            name: d.name,
            ownerName: d.dailyLeaderName,
            phone: d.phone,
            email: d.email,
            address: d.street,
            postalCode: d.postalCode,
            city: d.city,
            country: d.country ?? 'NO',
            vehicleCountRegistered: 0,
            brregSnapshot: d.raw,
            createdAt: DateTime.now(),
          ),
        );
        ok++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registrert $ok bedrifter. Åpne hver bedrift for å legge til MAVI og sjåfør.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int get _okCount => _rows.where((r) => r.details != null).length;
  int get _selectedCount => _rows.where((r) => r.selected && r.details != null).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masseimport Brreg'),
        actions: [
          if (_phase == 1)
            TextButton(
              onPressed: () => setState(() => _phase = 0),
              child: const Text('Tilbake'),
            ),
        ],
      ),
      body: Column(
        children: [
          PartnerWizardStepper(
            labels: const ['Lim inn', 'Forhåndsvis', 'Registrer'],
            current: _phase,
          ),
          Expanded(child: _phase == 0 ? _pastePhase() : _previewPhase()),
          if (_phase == 1) _bottomBar(),
        ],
      ),
    );
  }

  Widget _pastePhase() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PartnerSectionCard(
          icon: Icons.content_paste_go_rounded,
          iconColor: DriftProTheme.accentBlue,
          title: 'Lim inn bedrifter',
          subtitle: 'Org.nr (9 siffer) eller bedriftsnavn — ett per linje',
          children: [
            TextField(
              controller: _pasteCtrl,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: '912345678\nAcme Transport AS\n923456789',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _fetching ? null : _lookupBrreg,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _fetching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(_fetching ? 'Henter fra Brreg…' : 'Hent og forhåndsvis'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'Tips: Etter registrering åpner du hver bedrift og legger til MAVI-nummer og sjåfør under Oversikt.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _previewPhase() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _statChip('$_okCount funnet', DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              _statChip('$_selectedCount valgt', DriftProTheme.accentBlue),
              const Spacer(),
              TextButton(onPressed: _selectAll, child: const Text('Alle')),
              TextButton(onPressed: _selectNone, child: const Text('Ingen')),
            ],
          ),
        ),
        ..._rows.map(_previewTile),
      ],
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _previewTile(_BulkRow r) {
    final d = r.details;
    final ok = d != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: ok ? () => setState(() => r.selected = !r.selected) : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ok
                    ? (r.selected ? DriftProTheme.primaryGreen : Colors.grey.shade300)
                    : Colors.red.shade200,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Checkbox(
                  value: r.selected && ok,
                  onChanged: ok ? (v) => setState(() => r.selected = v ?? false) : null,
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d?.name ?? r.sourceLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: ok ? null : Colors.red.shade800,
                        ),
                      ),
                      if (d != null)
                        Text(
                          '${d.orgNumber} · ${d.city ?? ''} · ${d.dailyLeaderName ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: PartnerUi.mutedText(context)),
                        ),
                      if (r.error != null)
                        Text(r.error!, style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
                      if (r.warning != null)
                        Text(r.warning!, style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
                    ],
                  ),
                ),
                Icon(
                  ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 20,
                  color: ok ? DriftProTheme.primaryGreen : Colors.red,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _saving || _selectedCount == 0 ? null : _registerSelected,
          style: FilledButton.styleFrom(
            backgroundColor: DriftProTheme.primaryGreen,
            minimumSize: const Size.fromHeight(50),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.done_all),
          label: Text(_saving ? 'Registrerer…' : 'Registrer $_selectedCount bedrifter'),
        ),
      ),
    );
  }

  void _selectAll() {
    setState(() {
      for (final r in _rows) {
        if (r.details != null) r.selected = true;
      }
    });
  }

  void _selectNone() {
    setState(() {
      for (final r in _rows) {
        r.selected = false;
      }
    });
  }
}
