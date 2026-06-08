import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:signature/signature.dart';

import '../../../core/services/hms/hms_ecosystem_service.dart';
import '../../../core/services/hms/hms_pdf_generators.dart';
import '../widgets/hms_pdf_export_button.dart';
import '../../../core/services/storage/company_file_storage.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/hms_sja_step.dart';
import '../../../models/sja_form.dart';
import '../../../models/user_profile.dart';

class SjaDetailScreen extends StatefulWidget {
  final SjaForm form;

  const SjaDetailScreen({super.key, required this.form});

  @override
  State<SjaDetailScreen> createState() => _SjaDetailScreenState();
}

class _SjaDetailScreenState extends State<SjaDetailScreen> {
  late SjaForm _sja;
  UserProfile? _me;
  List<HmsSjaStep> _steps = [];
  List<HmsSjaSignature> _signatures = [];
  bool _loading = true;
  bool _signing = false;

  final SignatureController _sigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool get _isLeader =>
      _me?.isAdmin == true || _me?.role == UserRole.leder;

  bool get _hasSigned =>
      _me != null && _signatures.any((s) => s.profileId == _me!.id);

  bool get _allSigned => _signatures.length >= _sja.requiredSignatures;

  @override
  void initState() {
    super.initState();
    _sja = widget.form;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _me = await SupabaseService.fetchCurrentUserProfile();
      final fresh = await HmsEcosystemService.fetchSjaById(_sja.id);
      if (fresh != null) _sja = fresh;
      _steps = await HmsEcosystemService.fetchSjaSteps(_sja.id);
      _signatures = await HmsEcosystemService.fetchSjaSignatures(_sja.id);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signDigitally() async {
    if (_sigController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signer i feltet først')),
      );
      return;
    }
    setState(() => _signing = true);
    try {
      final bytes = await _sigController.toPngBytes();
      if (bytes == null) throw StateError('Kunne ikke eksportere signatur');
      final fileName =
          '${_me!.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = '${_sja.companyId}/sja/${_sja.id}/$fileName';
      final stored = await CompanyFileStorage.upload(
        supabaseBucket: 'sja',
        storagePath: path,
        bytes: bytes,
        category: 'hms',
        fileName: fileName,
      );
      final url = CompanyFileStorage.toStorageReference(stored);
      await HmsEcosystemService.registerSjaSignature(
        sjaId: _sja.id,
        method: 'digital',
        signatureUrl: url,
      );
      _sigController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signatur registrert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signering feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  Future<void> _startWork() async {
    try {
      await HmsEcosystemService.startSjaWork(_sja.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arbeid startet — aktivt tidsvindu er satt')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _showQrSheet() {
    final token = _sja.qrToken ?? _sja.id;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Skann for å signere SJA', style: DriftProTheme.headingSm),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  'driftpro://sja/$token',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: 'driftpro://sja/$token'));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lenke kopiert')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Kopier signatur-lenke'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPinSignSheet() async {
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team-PIN signering'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN fra leder',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bekreft')),
        ],
      ),
    );
    if (ok != true || pinController.text.trim().length < 4) return;

    setState(() => _signing = true);
    try {
      await HmsEcosystemService.registerSjaSignature(
        sjaId: _sja.id,
        method: 'pin',
        pinVerified: true,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PIN-signering feilet: $e')),
        );
      }
    } finally {
      pinController.dispose();
      if (mounted) setState(() => _signing = false);
    }
  }

  @override
  void dispose() {
    _sigController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(_sja.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          HmsPdfExportButton(
            fileName: 'sja_${_sja.id.substring(0, 8)}',
            onGenerate: () => HmsPdfGenerators.sja(
              _sja,
              steps: _steps,
              signatures: _signatures,
            ),
          ),
          if (_isLeader)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              onPressed: _showQrSheet,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusBanner(isDark, fmt),
                  const SizedBox(height: 16),
                  _buildInfoCard(isDark),
                  const SizedBox(height: 20),
                  _buildStepsSection(isDark),
                  const SizedBox(height: 20),
                  _buildSignaturesSection(isDark, fmt),
                  if (!_hasSigned && _sja.status != SjaStatus.utlopt) ...[
                    const SizedBox(height: 20),
                    _buildSignPanel(isDark),
                  ],
                  if (_allSigned && _sja.status != SjaStatus.iGang) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _startWork,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start arbeid (alle har signert)'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner(bool isDark, DateFormat fmt) {
    Color bg;
    String text;
    switch (_sja.status) {
      case SjaStatus.iGang:
        bg = Colors.teal;
        final rem = _sja.remainingWindow;
        text = rem != null
            ? 'I gang — ${rem.inHours}t ${rem.inMinutes.remainder(60)}m igjen av vurderingen'
            : 'I gang';
      case SjaStatus.utlopt:
        bg = Colors.deepOrange;
        text = 'Utløpt — ny sikkerhetsvurdering kreves';
      case SjaStatus.signert:
      case SjaStatus.godkjent:
        bg = DriftProTheme.success;
        text = 'Signert (${_signatures.length}/${_sja.requiredSignatures})';
      case SjaStatus.venterSignatur:
        bg = Colors.amber.shade800;
        text = 'Venter signatur (${_signatures.length}/${_sja.requiredSignatures})';
      default:
        bg = Colors.grey;
        text = _sja.status.label;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg),
      ),
      child: Text(text, style: TextStyle(color: bg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_sja.workDescription),
            if (_sja.location != null) ...[
              const SizedBox(height: 8),
              Text('Sted: ${_sja.location}', style: DriftProTheme.bodySm),
            ],
            const SizedBox(height: 8),
            Text(
              'Planlagt: ${DateFormat('dd.MM.yyyy').format(_sja.plannedDate)} · '
              'Aktivt vindu: ${_sja.activeWindowHours}t',
              style: DriftProTheme.bodySm,
            ),
            if (_sja.requiredPpe.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: _sja.requiredPpe
                    .map((p) => Chip(label: Text(p, style: const TextStyle(fontSize: 11))))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepsSection(bool isDark) {
    if (_steps.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Arbeidstrinn', style: DriftProTheme.headingSm),
        const SizedBox(height: 8),
        ..._steps.map(
          (s) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            child: ListTile(
              leading: CircleAvatar(child: Text('${s.stepOrder}')),
              title: Text(s.operation, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fare: ${s.hazard}'),
                  Text('Tiltak: ${s.measure}',
                      style: TextStyle(color: DriftProTheme.primaryGreen)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignaturesSection(bool isDark, DateFormat fmt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Signaturer', style: DriftProTheme.headingSm),
        const SizedBox(height: 8),
        if (_signatures.isEmpty)
          const Text('Ingen har signert ennå', style: TextStyle(color: Colors.grey))
        else
          ..._signatures.map(
            (s) => ListTile(
              leading: Icon(
                s.method == 'pin' ? Icons.pin : Icons.draw,
                color: DriftProTheme.primaryGreen,
              ),
              title: Text(s.profileName ?? s.profileId),
              subtitle: Text('${s.method.toUpperCase()} · ${fmt.format(s.signedAt)}'),
            ),
          ),
      ],
    );
  }

  Widget _buildSignPanel(bool isDark) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Digital signatur', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Signature(
                controller: _sigController,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sigController.clear,
                    child: const Text('Tøm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _signing ? null : _signDigitally,
                    child: _signing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Signer'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _signing ? null : _showPinSignSheet,
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Signer med Team-PIN'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skann QR for å åpne SJA fra deep link / token.
class SjaQrScanScreen extends StatefulWidget {
  const SjaQrScanScreen({super.key});

  @override
  State<SjaQrScanScreen> createState() => _SjaQrScanScreenState();
}

class _SjaQrScanScreenState extends State<SjaQrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    String? token;
    if (raw.contains('driftpro://sja/')) {
      token = raw.split('driftpro://sja/').last;
    } else {
      token = raw;
    }

    _handled = true;
    final sja = await HmsEcosystemService.fetchSjaByQrToken(token);
    if (!mounted) return;
    if (sja == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fant ikke SJA for denne koden')),
      );
      _handled = false;
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SjaDetailScreen(form: sja)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skann SJA-QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
