import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import 'new_partner_screen.dart';
import 'partner_detail_screen.dart';

/// Oversikt over samarbeidspartnere (interne brukere).
class PartnersDashboardScreen extends StatefulWidget {
  const PartnersDashboardScreen({super.key});

  @override
  State<PartnersDashboardScreen> createState() => _PartnersDashboardScreenState();
}

class _PartnersDashboardScreenState extends State<PartnersDashboardScreen> {
  List<Partner> _partners = [];
  bool _loading = true;
  String? _error;
  bool _autoDistributing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        setState(() {
          _loading = false;
          _error = 'Fant ikke bedrift for brukeren.';
        });
        return;
      }
      final list = await PartnerService.fetchPartners(companyId: cid);
      if (mounted) {
        setState(() {
          _partners = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewPartnerScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _pickAndAutoDistributeFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    await _autoDistributeFromPlatformFiles(picked.files);
  }

  Future<void> _pickFolderAndAutoDistribute() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mappevalg støttes ikke i web. Velg flere filer i stedet.')),
      );
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Velg mappe med rute-PDF');
    if (dir == null) return;
    final entries = await Directory(dir).list().toList();
    final pdfFiles = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    if (pdfFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fant ingen PDF-filer i valgt mappe.')),
      );
      return;
    }
    final files = <PlatformFile>[];
    for (final f in pdfFiles) {
      final bytes = await f.readAsBytes();
      files.add(
        PlatformFile(
          name: f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'route.pdf',
          size: bytes.length,
          bytes: bytes,
          path: f.path,
        ),
      );
    }
    await _autoDistributeFromPlatformFiles(files);
  }

  /// Kanonisk nøkkel: M + tall uten ledende nuller (M0044 og NO_O_M0044 → M44).
  String _normalizeUnitCode(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';

    final noOm = RegExp(
      r'NO\s*[_-]?\s*O\s*[_-]?\s*M(\d{1,5})\b',
      caseSensitive: false,
    ).firstMatch(s);
    if (noOm != null) {
      final n = int.tryParse(noOm.group(1)!);
      if (n != null) return 'M$n';
    }

    final mDigits = RegExp(r'\bM(\d{1,5})\b', caseSensitive: false).firstMatch(s);
    if (mDigits != null) {
      final n = int.tryParse(mDigits.group(1)!);
      if (n != null) return 'M$n';
    }

    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  Map<String, PartnerVehicle> _vehicleLookupMap(List<PartnerVehicle> rows) {
    final map = <String, PartnerVehicle>{};
    void putKey(String? key, PartnerVehicle v) {
      if (key == null || key.isEmpty) return;
      final k = _normalizeUnitCode(key);
      if (k.isNotEmpty) map.putIfAbsent(k, () => v);
      final compact = key.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
      if (compact.isNotEmpty) map.putIfAbsent(compact, () => v);
    }

    for (final v in rows) {
      putKey(v.unitCode, v);
      putKey(v.registrationNumber, v);
    }
    return map;
  }

  String? _parseResourceIdFromPdfText(String raw) {
    if (raw.isEmpty) return null;
    var t = raw.replaceAll('\uFF3F', '_').replaceAll('\u2013', '-');
    final attempts = <String>[t, t.replaceAll(RegExp(r'\s+'), ' ')];

    final patterns = <RegExp>[
      RegExp(r'NO\s*[_-]?\s*O\s*[_-]?\s*M(\d{1,5})', caseSensitive: false),
      RegExp(r'NO_O_(M\d{1,5})\b', caseSensitive: false),
      RegExp(r'\bM(\d{1,5})\b', caseSensitive: false),
    ];

    for (final text in attempts) {
      for (final re in patterns) {
        final m = re.firstMatch(text);
        if (m == null) continue;
        final g = m.groupCount >= 1 ? m.group(1) : null;
        if (g == null || g.isEmpty) continue;
        final up = g.toUpperCase();
        if (up.startsWith('M')) return up;
        return 'M$up';
      }
    }
    return null;
  }

  String? _extractVehicleCodeFromPdf(Uint8List bytes) {
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final lastPage = doc.pages.count - 1;
      final earlyEnd = lastPage > 2 ? 1 : lastPage;

      final layoutEarly = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: earlyEnd,
        layoutText: true,
      );
      final linearEarly = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: earlyEnd,
        layoutText: false,
      );
      var found = _parseResourceIdFromPdfText('$layoutEarly\n$linearEarly');
      if (found == null && lastPage > earlyEnd) {
        final rest = extractor.extractText(
          startPageIndex: earlyEnd + 1,
          endPageIndex: lastPage,
          layoutText: false,
        );
        found = _parseResourceIdFromPdfText(rest);
      }
      found ??= _parseResourceIdFromPdfText(extractor.extractText());
      doc.dispose();
      return found;
    } catch (_) {
      return null;
    }
  }

  String? _extractVehicleCodeFromFilename(String fileName) {
    final base = fileName.split(RegExp(r'[\\/]')).last;
    return _parseResourceIdFromPdfText(base.replaceAll('_', ' '));
  }

  Future<Uint8List?> _platformFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) return file.bytes;
    if (!kIsWeb && file.path != null) {
      try {
        return await File(file.path!).readAsBytes();
      } catch (_) {}
    }
    if (file.readStream != null) {
      final out = <int>[];
      await for (final chunk in file.readStream!) {
        out.addAll(chunk);
      }
      if (out.isEmpty) return null;
      return Uint8List.fromList(out);
    }
    return null;
  }

  Future<void> _autoDistributeFromPlatformFiles(List<PlatformFile> files) async {
    if (_autoDistributing) return;
    setState(() => _autoDistributing = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke company_id.');
      final partners = await PartnerService.fetchPartners(companyId: cid);
      final partnerById = {for (final p in partners) p.id: p};
      final vehicleRows = <PartnerVehicle>[];
      for (final p in partners) {
        final v = await PartnerService.fetchVehicles(p.id);
        vehicleRows.addAll(v);
      }
      final vehicleMap = _vehicleLookupMap(vehicleRows);

      int sent = 0;
      int skipped = 0;
      for (final file in files) {
        final bytes = await _platformFileBytes(file);
        if (bytes == null || bytes.isEmpty) {
          skipped++;
          continue;
        }
        var foundCode = _extractVehicleCodeFromPdf(bytes);
        foundCode ??= _extractVehicleCodeFromFilename(file.name);
        if (foundCode == null) {
          skipped++;
          continue;
        }
        final normalized = _normalizeUnitCode(foundCode);
        final compact = foundCode.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
        final vehicle = vehicleMap[normalized] ?? vehicleMap[compact];
        if (vehicle == null) {
          skipped++;
          continue;
        }
        final partner = partnerById[vehicle.partnerId];
        if (partner == null) {
          skipped++;
          continue;
        }
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath =
            'company_$cid/partner_routes/${DateTime.now().millisecondsSinceEpoch}_${vehicle.unitCode}_$safeName';
        await PartnerService.uploadPartnerRoutePdf(
          storagePath: storagePath,
          bytes: bytes,
        );
        await PartnerService.addRouteShare(
          PartnerRouteShare(
            id: '',
            partnerId: partner.id,
            companyId: cid,
            title: 'Rute ${vehicle.unitCode}',
            pdfStoragePath: storagePath,
            shareDate: DateTime.now(),
            isDailyShare: true,
            createdAt: DateTime.now(),
          ),
        );
        sent++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-fordeling ferdig: sendt $sent, hoppet over $skipped.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-fordeling feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _autoDistributing = false);
    }
  }

  Future<void> _openAutoDistributeDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Smart rutefordeling'),
                subtitle: Text('Leser PDF -> Resource ID (NO_O_Mxxxx) -> matcher bil/firma automatisk'),
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('Velg én eller flere PDF-filer'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickAndAutoDistributeFiles();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Velg mappe med PDF-filer'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickFolderAndAutoDistribute();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Samarbeidspartnere'),
        actions: [
          IconButton(
            tooltip: 'Smart rutefordeling',
            icon: _autoDistributing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            onPressed: _autoDistributing ? null : _openAutoDistributeDialog,
          ),
          IconButton(
            tooltip: 'Ny samarbeidspartner',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _openNew,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('Registrer partner'),
        backgroundColor: DriftProTheme.primaryGreen,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())])
            : _error != null
                ? ListView(
                    children: [
                      _buildMassOutputCard(),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _partners.isEmpty
                    ? ListView(
                        children: [
                          _buildMassOutputCard(),
                          SizedBox(height: 80),
                          Icon(Icons.handshake_outlined, size: 56, color: Colors.grey),
                          SizedBox(height: 16),
                          const Center(child: Text('Ingen samarbeidspartnere registrert ennå.')),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        children: [
                          _buildMassOutputCard(),
                          const SizedBox(height: 8),
                          ..._partners.map((p) {
                            return _PartnerCard(
                              partner: p,
                              onTap: () async {
                                await Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => PartnerDetailScreen(partner: p),
                                  ),
                                );
                                _load();
                              },
                            );
                          }),
                        ],
                      ),
      ),
    );
  }

  Widget _buildMassOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Massedistribuer ruter (smart PDF)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Leser Resource ID i PDF (NO_O_Mxxxx) og sender automatisk til riktig bil/firma.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _autoDistributing ? null : _pickAndAutoDistributeFiles,
                  icon: _autoDistributing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Velg PDF-filer'),
                ),
                OutlinedButton.icon(
                  onPressed: _autoDistributing ? null : _pickFolderAndAutoDistribute,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Velg mappe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  final Partner partner;
  final VoidCallback onTap;

  const _PartnerCard({required this.partner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.apartment_rounded, color: DriftProTheme.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(partner.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        if (partner.orgNumber != null)
                          Text('Org.nr ${partner.orgNumber}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _mini(Icons.person_outline, partner.ownerName ?? 'Eier ikke registrert'),
                  _mini(Icons.phone_outlined, partner.phone ?? '—'),
                  _mini(Icons.email_outlined, partner.email ?? '—'),
                ],
              ),
              if (partner.nextMeetingAt != null || partner.nextAuditAt != null) ...[
                const Divider(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    if (partner.nextMeetingAt != null)
                      Chip(
                        avatar: const Icon(Icons.event, size: 18),
                        label: Text('Møte ${_fmt(partner.nextMeetingAt!)}', style: const TextStyle(fontSize: 11)),
                      ),
                    if (partner.nextAuditAt != null)
                      Chip(
                        avatar: const Icon(Icons.fact_check, size: 18),
                        label: Text('Revisjon ${_date(partner.nextAuditAt!)}', style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[800])),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';
  static String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
