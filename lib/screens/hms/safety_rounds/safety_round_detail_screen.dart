import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/hms/hms_pdf_generators.dart';
import '../../../core/services/hms/safety_round_service.dart';
import '../widgets/hms_pdf_export_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/safety_round.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Arkivvisning – søkbar vernerunde med PDF-nedlasting.
class SafetyRoundDetailScreen extends StatefulWidget {
  final String roundId;

  const SafetyRoundDetailScreen({super.key, required this.roundId});

  @override
  State<SafetyRoundDetailScreen> createState() =>
      _SafetyRoundDetailScreenState();
}

class _SafetyRoundDetailScreenState extends State<SafetyRoundDetailScreen> {
  SafetyRound? _round;
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _round = await SafetyRoundService.fetchById(widget.roundId);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _downloadPdf() async {
    final r = _round;
    if (r == null) return;
    try {
      var url = r.pdfUrl;
      if (url == null || url.isEmpty) {
        final updated = await SafetyRoundService.finalizeWithPdf(r);
        url = updated.pdfUrl;
        _round = updated;
      }
      if (url != null && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF-feil: $e')));
      }
    }
  }

  Future<void> _regeneratePdf() async {
    final r = _round;
    if (r == null) return;
    setState(() => _loading = true);
    try {
      _round = await SafetyRoundService.finalizeWithPdf(r);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF oppdatert i arkiv')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredChecklist {
    final r = _round;
    if (r == null) return [];
    if (_filter.isEmpty) return r.checklist;
    final q = _filter.toLowerCase();
    return r.checklist.where((e) {
      final task = (e['task'] ?? '').toString().toLowerCase();
      final sec = (e['section_title'] ?? '').toString().toLowerCase();
      final com = (e['comment'] ?? '').toString().toLowerCase();
      return task.contains(q) || sec.contains(q) || com.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: const DriftProLoadingCenter(),
      );
    }
    final r = _round;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vernerunde')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Fant ikke vernerunde'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Prøv igjen'),
              ),
            ],
          ),
        ),
      );
    }

    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vernerunde – arkiv'),
        actions: [
          HmsPdfExportButton(
            fileName: 'vernerunde_${r.archiveNumber ?? r.id.substring(0, 8)}',
            onGenerate: () => HmsPdfGenerators.safetyRound(r),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Åpne arkivert PDF',
            onPressed: _downloadPdf,
          ),
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Generer PDF på nytt',
              onPressed: _regeneratePdf,
            ),
        ],
      ),
      body: Column(
        children: [
          _stampHeader(r, df),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Søk i sjekkliste...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ..._filteredChecklist.map((item) => _itemTile(item)),
                if (r.findings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Avvik', style: DriftProTheme.headingSm),
                  ...r.findings.map(
                    (f) => ListTile(
                      leading: const Icon(Icons.warning_amber, color: Colors.orange),
                      title: Text(f['description'] as String? ?? ''),
                      subtitle: Text(f['severity'] as String? ?? ''),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stampHeader(SafetyRound r, DateFormat df) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: DriftProTheme.primaryGreen, width: 2),
        borderRadius: BorderRadius.circular(12),
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              Text(
                r.archiveNumber ?? 'ARKIVERT',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.title, style: DriftProTheme.headingSm),
          Text('Utført: ${r.conductorName ?? "—"}'),
          if (r.location != null) Text('Sted: ${r.location}'),
          if (r.participantNames.isNotEmpty)
            Text('Deltakere: ${r.participantNames.join(", ")}'),
          if (r.roundNotes != null && r.roundNotes!.isNotEmpty)
            Text('Merknader: ${r.roundNotes}'),
          if (r.nextRoundDate != null)
            Text(
              'Neste runde: ${DateFormat('dd.MM.yyyy').format(r.nextRoundDate!)}',
            ),
          if (r.completedAt != null)
            Text('Fullført: ${df.format(r.completedAt!)}'),
          if (r.signedAt != null)
            Text(
              'Signert (${r.signerRole}): ${r.signedByName} – ${df.format(r.signedAt!)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 8),
          Text(
            'OK: ${r.okCount} · Avvik: ${r.avvikCount} · Totalt: ${r.checklist.length}',
            style: DriftProTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _itemTile(Map<String, dynamic> item) {
    final status = item['status'] as String? ?? 'pending';
    Color c = Colors.grey;
    if (status == 'ok') c = DriftProTheme.success;
    if (status == 'avvik') c = DriftProTheme.warning;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.withValues(alpha: 0.15),
          child: Text(
            status == 'ok' ? '✓' : status == 'avvik' ? '!' : '—',
            style: TextStyle(color: c, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(item['task'] as String? ?? ''),
        subtitle: Text(
          '${item['section_title'] ?? ""}\n${item['comment'] ?? ""}',
        ),
      ),
    );
  }
}
