import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/route_dispatch_report.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Resultat fra leveringsrapport: lukk wizard kun når alt er OK (eller tvangslukk).
class RouteDeliveryReportResult {
  const RouteDeliveryReportResult({
    required this.report,
    required this.closeWizard,
  });

  final RouteDispatchReport report;
  final bool closeWizard;
}

Future<RouteDeliveryReportResult?> showRouteDeliveryReportDialog({
  required BuildContext context,
  required String companyId,
  required RouteDispatchReport initialReport,
  Map<String, String>? driverLabels,
  Map<String, String?>? phones,
}) {
  return showDialog<RouteDeliveryReportResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PartnerRouteDeliveryReportDialog(
      companyId: companyId,
      initialReport: initialReport,
      driverLabels: driverLabels ?? const {},
      phones: phones ?? const {},
    ),
  );
}

/// Flush + verifiser + vis blokkerende rapport etter `dispatchRouteShares`.
Future<RouteDeliveryReportResult?> runPostDispatchDeliveryReport({
  required BuildContext context,
  required String companyId,
  required Iterable<String> shareIds,
  Map<String, String>? driverLabels,
  Map<String, String?>? phones,
}) async {
  final report = await PartnerService.finalizeRouteDispatchReport(
    companyId: companyId,
    shareIds: shareIds,
    driverLabels: driverLabels,
    phones: phones,
  );
  if (!context.mounted) return null;
  return showRouteDeliveryReportDialog(
    context: context,
    companyId: companyId,
    initialReport: report,
    driverLabels: driverLabels,
    phones: phones,
  );
}

class PartnerRouteDeliveryReportDialog extends StatefulWidget {
  const PartnerRouteDeliveryReportDialog({
    super.key,
    required this.companyId,
    required this.initialReport,
    this.driverLabels = const {},
    this.phones = const {},
  });

  final String companyId;
  final RouteDispatchReport initialReport;
  final Map<String, String> driverLabels;
  final Map<String, String?> phones;

  @override
  State<PartnerRouteDeliveryReportDialog> createState() =>
      _PartnerRouteDeliveryReportDialogState();
}

class _PartnerRouteDeliveryReportDialogState
    extends State<PartnerRouteDeliveryReportDialog> {
  late RouteDispatchReport _report;
  bool _busy = false;
  String? _busyShareId;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport;
    // Når alt er OK: lukk automatisk så AUTO MASS forsvinner uten ekstra klikk.
    if (_report.allOk) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted && _report.allOk) {
            _close(closeWizard: true);
          }
        });
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final next = await PartnerService.finalizeRouteDispatchReport(
        companyId: widget.companyId,
        shareIds: _report.rows.map((r) => r.shareId),
        driverLabels: widget.driverLabels,
        phones: widget.phones,
      );
      if (!mounted) return;
      setState(() => _report = next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend(String shareId) async {
    setState(() {
      _busy = true;
      _busyShareId = shareId;
    });
    try {
      await PartnerService.notifyRouteShareSms(shareId);
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyShareId = null;
        });
      }
    }
  }

  Future<void> _resendAllFailed() async {
    final failed = _report.failedRows;
    if (failed.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final row in failed) {
        await PartnerService.notifyRouteShareSms(row.shareId);
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPdf(RouteDispatchReportRow row) async {
    try {
      final path = (row.delivery.pdfStoragePath ?? '').trim();
      if (path.isEmpty) {
        throw StateError('PDF-sti mangler');
      }
      final url = await PartnerService.getRoutePdfSignedUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunne ikke åpne PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _call(String? phone) async {
    final p = (phone ?? '').trim();
    if (p.length < 8) return;
    final uri = Uri(scheme: 'tel', path: p.replaceAll(RegExp(r'[^\d+]'), ''));
    await launchUrl(uri);
  }

  void _copyFailures() {
    Clipboard.setData(ClipboardData(text: _report.failureListText()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Feilliste kopiert')),
    );
  }

  void _close({required bool closeWizard}) {
    Navigator.pop(
      context,
      RouteDeliveryReportResult(report: _report, closeWizard: closeWizard),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allOk = _report.allOk;
    final headerColor =
        allOk ? DriftProTheme.primaryGreen : const Color(0xFFB91C1C);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      title: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: headerColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              allOk ? 'Alle ruter levert' : 'Ikke levert — handling kreves',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              allOk
                  ? '${_report.okCount} av ${_report.totalCount} OK (PDF + SMS/push)'
                  : '${_report.failedCount} av ${_report.totalCount} ruter mangler PDF, SMS eller push',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: _busy && _report.rows.isEmpty
              ? const SizedBox(
                  height: 160,
                  child: DriftProLoadingCenter(),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _report.rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final row = _report.rows[i];
                    return _ReportTile(
                      row: row,
                      busy: _busy && _busyShareId == row.shareId,
                      onResend: () => _resend(row.shareId),
                      onOpenPdf: () => _openPdf(row),
                      onCall: row.phone != null && row.phone!.trim().length >= 8
                          ? () => _call(row.phone)
                          : null,
                    );
                  },
                ),
        ),
      ),
      actions: [
        if (!allOk) ...[
          TextButton(
            onPressed: _busy ? null : _copyFailures,
            child: const Text('Kopier feilliste'),
          ),
          TextButton(
            onPressed: _busy ? null : _resendAllFailed,
            child: const Text('Send alle feilede på nytt'),
          ),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Oppdater status'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
            ),
            onPressed: _busy ? null : () => _close(closeWizard: true),
            child: const Text('Ferdig — lukk AUTO MASS'),
          ),
        ] else ...[
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Oppdater'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
            ),
            onPressed: _busy ? null : () => _close(closeWizard: true),
            child: const Text('Ferdig'),
          ),
        ],
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.row,
    required this.busy,
    required this.onResend,
    required this.onOpenPdf,
    this.onCall,
  });

  final RouteDispatchReportRow row;
  final bool busy;
  final VoidCallback onResend;
  final VoidCallback onOpenPdf;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final ok = row.isOk;
    final border = ok ? Colors.green.shade300 : Colors.red.shade300;
    final bg = ok ? Colors.green.shade50 : Colors.red.shade50;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: ok ? Colors.green.shade800 : Colors.red.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.displayTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: ok ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
              ),
            ],
          ),
          if ((row.driverLabel ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              row.driverLabel!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip('PDF', row.pdfOk),
              _chip('Dropbox', row.storageIsDropbox),
              _chip(
                'SMS',
                !row.delivery.prefs.sms || row.delivery.smsOk,
                muted: !row.delivery.prefs.sms,
              ),
              _chip(
                'Push',
                !row.delivery.prefs.app || row.delivery.appOk,
                muted: !row.delivery.prefs.app,
              ),
            ],
          ),
          if (!ok) ...[
            const SizedBox(height: 6),
            Text(
              row.statusLine,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade900,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: busy ? null : onOpenPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('PDF'),
              ),
              TextButton.icon(
                onPressed: busy ? null : onResend,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sms_outlined, size: 16),
                label: const Text('Send på nytt'),
              ),
              if (onCall != null)
                TextButton.icon(
                  onPressed: busy ? null : onCall,
                  icon: const Icon(Icons.phone_outlined, size: 16),
                  label: const Text('Ring'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool ok, {bool muted = false}) {
    final color = muted
        ? Colors.grey
        : (ok ? Colors.green.shade800 : Colors.red.shade800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        muted ? '$label —' : (ok ? '$label ✓' : '$label ✗'),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
