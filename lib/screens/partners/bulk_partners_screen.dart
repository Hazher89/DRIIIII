import 'package:flutter/material.dart';

import '../../core/services/brreg_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';

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

/// Lim inn mange org.nr (9 siffer) eller bedriftsnavn — hent fra Brreg og registrer valgte.
class BulkPartnersScreen extends StatefulWidget {
  const BulkPartnersScreen({super.key});

  @override
  State<BulkPartnersScreen> createState() => _BulkPartnersScreenState();
}

class _BulkPartnersScreenState extends State<BulkPartnersScreen> {
  final _pasteCtrl = TextEditingController();
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
          if (d == null) {
            out.add(_BulkRow(sourceLine: line, error: 'Fant ikke org.nr i Brreg'));
          } else {
            out.add(_BulkRow(sourceLine: line, details: d));
          }
        } else {
          final hits = await BrregService.searchByName(line);
          if (hits.isEmpty) {
            out.add(_BulkRow(sourceLine: line, error: 'Ingen treff på navn'));
          } else if (hits.length == 1) {
            final d = await BrregService.fetchByOrgNumber(hits.first.orgNumber);
            if (d == null) {
              out.add(_BulkRow(sourceLine: line, error: 'Kunne ikke hente detaljer'));
            } else {
              out.add(_BulkRow(sourceLine: line, details: d));
            }
          } else {
            final d = await BrregService.fetchByOrgNumber(hits.first.orgNumber);
            if (d == null) {
              out.add(_BulkRow(sourceLine: line, error: 'Kunne ikke hente detaljer'));
            } else {
              out.add(_BulkRow(
                sourceLine: line,
                details: d,
                warning: 'Flere treff — brukte: ${hits.first.name} (${hits.first.orgNumber})',
              ));
            }
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
      });
    }
  }

  Future<void> _registerSelected() async {
    final picked = _rows.where((r) => r.selected && r.details != null).toList();
    if (picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én bedrift med gyldig Brreg-data.')),
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
        final p = Partner(
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
        );
        await PartnerService.createPartner(p);
        ok++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registrert $ok samarbeidspartnere. Legg til biler og portal under hver bedrift.')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masseimport (Brreg)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lim inn flere org.nr (9 siffer) eller bedriftsnavn. Skill med linjeskift, komma eller semikolon.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pasteCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Org.nr / navn',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _fetching ? null : _lookupBrreg,
                  style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                  icon: _fetching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: Text(_fetching ? 'Henter fra Brreg…' : 'Hent data fra Brreg'),
                ),
              ],
            ),
          ),
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      for (final r in _rows) {
                        r.selected = true;
                      }
                    }),
                    child: const Text('Velg alle'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      for (final r in _rows) {
                        r.selected = false;
                      }
                    }),
                    child: const Text('Velg ingen'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _registerSelected,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Registrer valgte'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _rows.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final d = r.details;
                      return Card(
                        child: CheckboxListTile(
                          value: r.selected,
                          onChanged: d == null && r.error != null
                              ? null
                              : (v) => setState(() => r.selected = v ?? false),
                          title: Text(
                            d?.name ?? r.sourceLine,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: r.error != null ? Colors.red[800] : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (d != null) Text('Org.nr ${d.orgNumber} · ${d.city ?? ''}'),
                              if (r.error != null) Text(r.error!, style: const TextStyle(color: Colors.red)),
                              if (r.warning != null)
                                Text(r.warning!, style: TextStyle(fontSize: 12, color: Colors.orange[800])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
