import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/permissions/user_access.dart';
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
    if (_batch == null || (_batch!.scans.isEmpty)) return;
    setState(() => _submitting = true);
    try {
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
                          batch: _batch!,
                          onBatchChanged: _reloadBatch,
                          onSubmit: _submit,
                          submitting: _submitting,
                        ),
                        GmStoroAdminPanel(isSuperAdmin: _profile?.isSuperAdmin == true),
                      ],
                    )
                  : _GmStoroScanPanel(
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
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final _picker = ImagePicker();

  String? _lastBarcode;
  DateTime? _lastScanAt;
  bool _processing = false;
  Color _flashColor = Colors.transparent;
  final Set<String> _localSscc = {};

  @override
  void initState() {
    super.initState();
    _syncLocalSscc();
  }

  @override
  void didUpdateWidget(covariant _GmStoroScanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.batch.id != widget.batch.id) _syncLocalSscc();
  }

  void _syncLocalSscc() {
    _localSscc
      ..clear()
      ..addAll(
        widget.batch.scans
            .map((s) => GmStoroLabelParser.normalizeSscc(s.data.sscc))
            .where((s) => s.isNotEmpty),
      );
  }

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _flash(Color color) async {
    setState(() => _flashColor = color);
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (mounted) setState(() => _flashColor = Colors.transparent);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    final now = DateTime.now();
    if (_lastBarcode == raw &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 1800)) {
      return;
    }
    _lastBarcode = raw;
    _lastScanAt = now;

    setState(() => _processing = true);
    try {
      var data = GmStoroLabelParser.parseBarcode(raw);
      await _register(data);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _register(GmStoroLabelData data) async {
    final outcome = await GmStoroService.instance.registerScan(
      batchId: widget.batch.id,
      data: data,
      localSsccKeys: _localSscc,
    );

    if (!mounted) return;

    switch (outcome.result) {
      case GmStoroScanResult.duplicate:
        await _flash(Colors.red.withValues(alpha: 0.35));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dobbel skann! SSCC ${outcome.sscc} finnes allerede.'),
            backgroundColor: DriftProTheme.error,
            duration: const Duration(milliseconds: 1200),
          ),
        );
        break;
      case GmStoroScanResult.invalid:
        await _flash(Colors.orange.withValues(alpha: 0.3));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kunne ikke lese etiketten — bruk kamera-ikon for full lesing'),
            backgroundColor: DriftProTheme.warning,
            duration: Duration(milliseconds: 1500),
          ),
        );
        break;
      case GmStoroScanResult.success:
        _localSscc.add(outcome.sscc!);
        await _flash(DriftProTheme.success.withValues(alpha: 0.35));
        await widget.onBatchChanged();
        break;
    }
  }

  Future<void> _captureLabelPhoto() async {
    if (_processing) return;
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (file == null || !mounted) return;

    setState(() => _processing = true);
    try {
      var data = const GmStoroLabelData();
      final capture = await _scannerCtrl.analyzeImage(file.path);
      if (capture != null) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        data = GmStoroLabelParser.parseBarcode(raw);
      }
      final ocr = await recognizeLabelFromPath(file.path);
      if (ocr != null && ocr.isNotEmpty) {
        data = data.merge(GmStoroLabelParser.parseOcrText(ocr));
      }
      await _register(data);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scans = widget.batch.scans;
    final validCount = scans.where((s) => !s.isDuplicate).length;

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _scannerCtrl, onDetect: _onDetect),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: _flashColor,
              ),
              if (_processing)
                Container(
                  color: Colors.black26,
                  child: const Center(child: DriftProLoadingIndicator()),
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
                    'Hold etiketten i rammen — strekkode leses automatisk',
                    textAlign: TextAlign.center,
                    style: DriftProTheme.caption.copyWith(color: Colors.white),
                  ),
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
                tooltip: 'Les hele etiketten med kamera',
                onPressed: _processing ? null : _captureLabelPhoto,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
            ],
          ),
        ),
        Expanded(
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
                        'Skann en etikett — den blir grønn når den er registrert',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.scan});

  final GmStoroScanRecord scan;

  @override
  Widget build(BuildContext context) {
    final d = scan.data;
    final isOk = !scan.isDuplicate;

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
          child: Icon(
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
          ].join(' · '),
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
