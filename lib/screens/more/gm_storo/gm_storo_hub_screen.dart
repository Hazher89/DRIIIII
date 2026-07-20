import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/native_permissions_service.dart';
import '../../../core/services/gm_storo/gm_storo_label_parser.dart';
import '../../../core/services/gm_storo/gm_storo_ocr.dart';
import '../../../core/services/gm_storo/gm_storo_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/gm_storo_scan.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'gm_storo_admin_panel.dart';

/// GM & STORO — rask skanning av hub-etiketter.
class GmStoroHubScreen extends StatefulWidget {
  const GmStoroHubScreen({super.key});

  @override
  State<GmStoroHubScreen> createState() => _GmStoroHubScreenState();
}

class _GmStoroHubScreenState extends State<GmStoroHubScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  UserProfile? _profile;
  GmStoroBatch? _batch;
  bool _loading = true;
  bool _submitting = false;

  bool get _isAdmin =>
      _profile?.isSuperAdmin == true ||
      _profile?.role == UserRole.admin ||
      _profile?.role == UserRole.leder;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final profile = await SupabaseService.fetchEffectiveUserProfile();
    final batch = await GmStoroService.instance.getOrCreateDraftBatch();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _batch = batch;
      _loading = false;
      if (_isAdmin) {
        _tabs = TabController(length: 2, vsync: this);
      }
    });
  }

  Future<void> _reloadBatch() async {
    if (_batch == null) return;
    final fresh = await GmStoroService.instance.fetchBatch(_batch!.id);
    if (mounted) setState(() => _batch = fresh);
  }

  Future<void> _submit() async {
    if (_batch == null) return;
    setState(() => _submitting = true);
    try {
      final fresh = await GmStoroService.instance.fetchBatch(_batch!.id);
      if (fresh == null || fresh.scans.where((s) => !s.isDuplicate).isEmpty) {
        return;
      }
      setState(() => _batch = fresh);

      final ok = await GmStoroService.instance.submitBatch(_batch!.id);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sendt til superadmin! Du kan starte ny skanning.'),
            backgroundColor: DriftProTheme.success,
          ),
        );
        final next = await GmStoroService.instance.getOrCreateDraftBatch();
        setState(() => _batch = next);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('GM & STORO'),
        bottom: _isAdmin && _tabs != null
            ? TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(icon: Icon(Icons.qr_code_scanner), text: 'Skann'),
                  Tab(icon: Icon(Icons.dashboard_outlined), text: 'Oversikt'),
                ],
              )
            : null,
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _batch == null
              ? const Center(child: Text('Kunne ikke starte skanning'))
              : _isAdmin && _tabs != null
                  ? TabBarView(
                      controller: _tabs,
                      children: [
                        _GmStoroScanPanel(
                          key: ValueKey(_batch!.id),
                          batch: _batch!,
                          onBatchChanged: _reloadBatch,
                          onSubmit: _submit,
                          submitting: _submitting,
                        ),
                        GmStoroAdminPanel(isSuperAdmin: _profile?.isSuperAdmin == true),
                      ],
                    )
                  : _GmStoroScanPanel(
                      key: ValueKey(_batch!.id),
                      batch: _batch!,
                      onBatchChanged: _reloadBatch,
                      onSubmit: _submit,
                      submitting: _submitting,
                    ),
    );
  }
}

class _GmStoroScanPanel extends StatefulWidget {
  const _GmStoroScanPanel({
    super.key,
    required this.batch,
    required this.onBatchChanged,
    required this.onSubmit,
    required this.submitting,
  });

  final GmStoroBatch batch;
  final Future<void> Function() onBatchChanged;
  final Future<void> Function() onSubmit;
  final bool submitting;

  @override
  State<_GmStoroScanPanel> createState() => _GmStoroScanPanelState();
}

class _GmStoroScanPanelState extends State<_GmStoroScanPanel> {
  final _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.unrestricted,
    facing: CameraFacing.back,
  );
  final _picker = ImagePicker();

  bool _ocrBusy = false;
  Color _flashColor = Colors.transparent;
  final Set<String> _localSscc = {};
  final Set<String> _inflightSscc = {};
  final Map<String, DateTime> _lastSsccAt = {};
  final List<GmStoroScanRecord> _sessionScans = [];

  @override
  void initState() {
    super.initState();
    _hydrateFromBatch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NativePermissionsService.ensureCamera(context: context);
    });
  }

  @override
  void didUpdateWidget(covariant _GmStoroScanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batch.id != widget.batch.id) _hydrateFromBatch();
  }

  void _hydrateFromBatch() {
    _localSscc
      ..clear()
      ..addAll(
        widget.batch.scans
            .map((s) => GmStoroLabelParser.normalizeSscc(s.data.sscc))
            .where((s) => s.length == 18),
      );
    _sessionScans
      ..clear()
      ..addAll(widget.batch.scans);
  }

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  void _flash(Color color) {
    setState(() => _flashColor = color);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flashColor = Colors.transparent);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_ocrBusy) return;

    final data = GmStoroLabelParser.parseFromCapture(capture);
    if (!data.hasMinimumData) return;

    final ssccKey = GmStoroLabelParser.normalizeSscc(data.sscc);
    if (ssccKey.length != 18) return;

    final now = DateTime.now();
    final last = _lastSsccAt[ssccKey];
    if (last != null && now.difference(last) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastSsccAt[ssccKey] = now;

    if (_localSscc.contains(ssccKey)) {
      _flash(Colors.red.withValues(alpha: 0.4));
      HapticFeedback.heavyImpact();
      return;
    }
    if (_inflightSscc.contains(ssccKey)) return;

    _inflightSscc.add(ssccKey);
    _localSscc.add(ssccKey);

    final optimistic = GmStoroScanRecord(
      id: 'pending-$ssccKey',
      batchId: widget.batch.id,
      data: data.copyWithSscc(ssccKey),
      scannedAt: now,
    );

    setState(() => _sessionScans.insert(0, optimistic));
    _flash(DriftProTheme.success.withValues(alpha: 0.4));
    HapticFeedback.lightImpact();

    unawaited(_persistScan(ssccKey, data));
  }

  Future<void> _persistScan(String ssccKey, GmStoroLabelData data) async {
    try {
      final outcome = await GmStoroService.instance.registerScan(
        batchId: widget.batch.id,
        data: data,
        localSsccKeys: Set<String>.from(_localSscc)..remove(ssccKey),
      );

      if (!mounted) return;

      switch (outcome.result) {
        case GmStoroScanResult.duplicate:
          _localSscc.remove(ssccKey);
          setState(() {
            _sessionScans.removeWhere((s) => s.id == 'pending-$ssccKey');
            _markDuplicate(ssccKey);
          });
          _flash(Colors.red.withValues(alpha: 0.4));
          HapticFeedback.heavyImpact();
        case GmStoroScanResult.invalid:
          _localSscc.remove(ssccKey);
          setState(() {
            _sessionScans.removeWhere((s) => s.id == 'pending-$ssccKey');
          });
          _flash(Colors.orange.withValues(alpha: 0.35));
        case GmStoroScanResult.success:
          final record = outcome.record;
          if (record != null) {
            setState(() {
              final i = _sessionScans.indexWhere((s) => s.id == 'pending-$ssccKey');
              if (i >= 0) _sessionScans[i] = record;
            });
          }
      }
    } catch (_) {
      if (!mounted) return;
      _localSscc.remove(ssccKey);
      setState(() {
        _sessionScans.removeWhere((s) => s.id == 'pending-$ssccKey');
      });
      _flash(Colors.orange.withValues(alpha: 0.35));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nettverksfeil — prøv å skanne på nytt'),
          duration: Duration(milliseconds: 1200),
        ),
      );
    } finally {
      _inflightSscc.remove(ssccKey);
    }
  }

  void _markDuplicate(String ssccKey) {
    final idx = _sessionScans.indexWhere(
      (s) => GmStoroLabelParser.normalizeSscc(s.data.sscc) == ssccKey,
    );
    if (idx < 0) return;
    final s = _sessionScans[idx];
    _sessionScans[idx] = GmStoroScanRecord(
      id: s.id,
      batchId: s.batchId,
      data: s.data,
      scannedAt: s.scannedAt,
      isDuplicate: true,
      scannerName: s.scannerName,
    );
  }

  Future<void> _captureLabelPhoto() async {
    if (_ocrBusy) return;
    if (!await NativePermissionsService.ensureCamera(context: context)) return;
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (file == null || !mounted) return;

    setState(() => _ocrBusy = true);
    try {
      var data = const GmStoroLabelData();
      final capture = await _scannerCtrl.analyzeImage(file.path);
      if (capture != null) {
        data = GmStoroLabelParser.parseFromCapture(capture);
      }
      final ocr = await recognizeLabelFromPath(file.path);
      if (ocr != null && ocr.isNotEmpty) {
        data = data.merge(GmStoroLabelParser.parseOcrText(ocr));
      }

      if (!data.hasMinimumData) {
        if (!mounted) return;
        _flash(Colors.orange.withValues(alpha: 0.35));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fant ikke kollinummer (SSCC) — hold strekkoden tydelig i rammen'),
            backgroundColor: DriftProTheme.warning,
            duration: Duration(milliseconds: 1800),
          ),
        );
        return;
      }

      final ssccKey = GmStoroLabelParser.normalizeSscc(data.sscc);
      if (_localSscc.contains(ssccKey)) {
        _flash(Colors.red.withValues(alpha: 0.4));
        return;
      }

      _localSscc.add(ssccKey);
      final optimistic = GmStoroScanRecord(
        id: 'pending-$ssccKey',
        batchId: widget.batch.id,
        data: data.copyWithSscc(ssccKey),
        scannedAt: DateTime.now(),
      );
      setState(() => _sessionScans.insert(0, optimistic));
      _flash(DriftProTheme.success.withValues(alpha: 0.4));
      await _persistScan(ssccKey, data);
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<void> _toggleTorch() async {
    await _scannerCtrl.toggleTorch();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scans = _sessionScans;
    final validCount = scans.where((s) => !s.isDuplicate).length;
    final torchOn = _scannerCtrl.value.torchState == TorchState.on;

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _scannerCtrl,
                onDetect: _onDetect,
                fit: BoxFit.cover,
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                color: _flashColor,
              ),
              if (_ocrBusy)
                Container(
                  color: Colors.black26,
                  child: const Center(child: DriftProLoadingIndicator()),
                ),
              Positioned(
                left: 16,
                right: 16,
                top: 12,
                child: Center(
                  child: Container(
                    width: 280,
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Hold strekkoden i rammen — kollinummer registreres automatisk',
                    textAlign: TextAlign.center,
                    style: DriftProTheme.caption.copyWith(color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: torchOn ? 'Slå av lommelykt' : 'Slå på lommelykt',
                  onPressed: _toggleTorch,
                  icon: Icon(
                    torchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                  ),
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _statChip(Icons.check_circle, '$validCount registrert', DriftProTheme.success),
              const SizedBox(width: 8),
              _statChip(Icons.qr_code_2, 'GM + Storo', DriftProTheme.accentBlue),
              const Spacer(),
              IconButton(
                tooltip: 'Les hele etiketten med kamera (valgfritt)',
                onPressed: _ocrBusy ? null : _captureLabelPhoto,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: scans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Ingen etiketter ennå', style: DriftProTheme.headingSm),
                      const SizedBox(height: 4),
                      Text(
                        'Skann strekkoden — kolli blir grønt med én gang',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: scans.length,
                  itemBuilder: (context, i) => _ScanCard(scan: scans[i]),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: validCount == 0 || widget.submitting ? null : widget.onSubmit,
              icon: widget.submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: DriftProLoadingIndicator(size: 18),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text('Send ($validCount)'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: DriftProTheme.primaryGreen,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

extension _GmStoroLabelDataSscc on GmStoroLabelData {
  GmStoroLabelData copyWithSscc(String sscc) {
    return GmStoroLabelData(
      sscc: sscc,
      barcodeRaw: barcodeRaw,
      packageId: packageId,
      shipmentId: shipmentId,
      consignee: consignee,
      recipientName: recipientName,
      recipientAddress: recipientAddress,
      recipientPostal: recipientPostal,
      weightKg: weightKg,
      readyTime: readyTime,
      readyDate: readyDate,
      articleEg: articleEg,
      articleNdc: articleNdc,
      areaCode: areaCode,
      unitType: unitType,
      senderName: senderName,
      destination: destination,
      rawText: rawText,
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.scan});

  final GmStoroScanRecord scan;

  @override
  Widget build(BuildContext context) {
    final d = scan.data;
    final isOk = !scan.isDuplicate;
    final isPending = scan.id.startsWith('pending-');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isOk ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOk ? DriftProTheme.success : DriftProTheme.error,
          width: isOk ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOk ? DriftProTheme.success : DriftProTheme.error,
          child: isPending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  isOk ? Icons.check : Icons.warning_amber,
                  color: Colors.white,
                ),
        ),
        title: Text(
          d.sscc ?? 'Ukjent SSCC',
          style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace'),
        ),
        subtitle: Text(
          [
            if (d.destination != null) d.destinationLabel,
            if (d.packageId != null) 'Pkg ${d.packageId}',
            if (d.shipmentId != null) 'Ship ${d.shipmentId}',
            if (d.consignee != null) 'Cons ${d.consignee}',
            if (d.weightKg != null) d.weightKg,
          ].nonNulls.where((s) => s.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          d.readyTime ?? '',
          style: DriftProTheme.caption,
        ),
      ),
    );
  }
}
