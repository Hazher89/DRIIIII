import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../../../models/user_profile.dart';
import '../../../core/case_trace/case_trace_chip.dart';
import 'partner_deduction_evidence_gallery.dart';
import 'partner_deduction_lock_dialogs.dart';
import 'partner_deduction_logiqrma_panel.dart';
import 'partner_modern_ui.dart';

class PartnerDeductionCaseSheet extends StatefulWidget {
  const PartnerDeductionCaseSheet({
    super.key,
    required this.caseRow,
    required this.partner,
    required this.onChanged,
    this.profile,
    this.canManageArchive = false,
    this.canUnlockAndDelete = false,
    this.onMarkInvoiced,
  });

  final PartnerDeductionCase caseRow;
  final Partner partner;
  final VoidCallback onChanged;
  final UserProfile? profile;
  final bool canManageArchive;
  final bool canUnlockAndDelete;
  final Future<void> Function()? onMarkInvoiced;

  static Future<void> show(
    BuildContext context, {
    required PartnerDeductionCase caseRow,
    required Partner partner,
    required VoidCallback onChanged,
    UserProfile? profile,
    bool canManageArchive = false,
    bool canUnlockAndDelete = false,
    Future<void> Function()? onMarkInvoiced,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scroll) => SingleChildScrollView(
          controller: scroll,
          child: PartnerDeductionCaseSheet(
            caseRow: caseRow,
            partner: partner,
            onChanged: onChanged,
            profile: profile,
            canManageArchive: canManageArchive,
            canUnlockAndDelete: canUnlockAndDelete,
            onMarkInvoiced: onMarkInvoiced,
          ),
        ),
      ),
    );
  }

  @override
  State<PartnerDeductionCaseSheet> createState() => _PartnerDeductionCaseSheetState();
}

class _PartnerDeductionCaseSheetState extends State<PartnerDeductionCaseSheet> {
  late PartnerDeductionCase _case = widget.caseRow;
  bool _busy = false;
  int _galleryKey = 0;
  Future<void> _unlockCase() async {
    final ok = await PartnerDeductionLockDialogs.confirmUnlock(
      context,
      caseNumber: _case.caseNumber,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await PartnerDeductionService.unlockCase(_case.id);
      if (!mounted) return;
      setState(() => _case = updated.copyPreservingListFields(_case));
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saken er låst opp')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCase() async {
    final comment = await PartnerDeductionLockDialogs.confirmDelete(
      context,
      caseNumber: _case.caseNumber,
    );
    if (comment == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await PartnerDeductionService.softDeleteCase(
        caseId: _case.id,
        deletionComment: comment,
      );
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saken er flyttet til slettet-arkiv')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend({
    required bool sms,
    required bool email,
    bool push = false,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await PartnerDeductionService.resendNotification(
        caseId: _case.id,
        notifySms: sms,
        notifyEmail: email,
        notifyPush: push,
      );
      await PartnerDeductionService.flushOutbox();
      if (!mounted) return;
      setState(() => _case = updated);
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Varsel sendt på nytt')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'mp4', 'mov', 'webm', 'm4v'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;

    setState(() => _busy = true);
    try {
      for (final f in result.files) {
        if (f.bytes == null) continue;
        await PartnerDeductionService.uploadEvidence(
          companyId: cid,
          partnerId: widget.partner.id,
          caseId: _case.id,
          caseNumber: _case.caseNumber,
          file: PartnerDeductionPendingEvidence(
            fileName: f.name,
            bytes: f.bytes!,
            extension: f.extension,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _galleryKey++;
        _case = PartnerDeductionCase(
          id: _case.id,
          companyId: _case.companyId,
          partnerId: _case.partnerId,
          partnerName: _case.partnerName,
          caseNumber: _case.caseNumber,
          templateId: _case.templateId,
          templateTitle: _case.templateTitle,
          shortDescription: _case.shortDescription,
          comment: _case.comment,
          amountNok: _case.amountNok,
          status: _case.status,
          createdBy: _case.createdBy,
          createdByName: _case.createdByName,
          createdAt: _case.createdAt,
          notifiedAt: _case.notifiedAt,
          smsSent: _case.smsSent,
          emailSent: _case.emailSent,
          invoicedAt: _case.invoicedAt,
          invoicedBy: _case.invoicedBy,
          invoicedByName: _case.invoicedByName,
          evidenceCount: _case.evidenceCount + result.files.where((f) => f.bytes != null).length,
          logiqrmaCaseNumber: _case.logiqrmaCaseNumber,
          voucherNumber: _case.voucherNumber,
          logisticsDescription: _case.logisticsDescription,
          isLocked: _case.isLocked,
          lockedAt: _case.lockedAt,
          unlockedAt: _case.unlockedAt,
          unlockedByName: _case.unlockedByName,
          deletedAt: _case.deletedAt,
          deletedByName: _case.deletedByName,
          deletionComment: _case.deletionComment,
        );
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bevis lagt til')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.displayTraceRef, style: DriftProTheme.headingMd),
          CaseTraceChip(traceRef: c.displayTraceRef, id: c.id),
          const SizedBox(height: 4),
          Text(widget.partner.name, style: TextStyle(color: PartnerModernUi.muted(context))),
          const SizedBox(height: 8),
          if (c.isLocked && !c.isDeleted) _lockBanner(c),
          if (c.isDeleted && widget.canUnlockAndDelete) _deletionAudit(c, df),
          ..._sakTab(c, money, df),
          if (widget.canUnlockAndDelete && c.isLocked && !c.isDeleted) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _unlockCase,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Lås opp fakturert sak'),
            ),
          ],
          if (widget.canUnlockAndDelete &&
              c.isInvoiced &&
              !c.isLocked &&
              !c.isDeleted) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _deleteCase,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Slett til arkiv'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.error,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
          if (widget.canManageArchive && !c.isInvoiced && !c.isDeleted && widget.onMarkInvoiced != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Økonomi', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Superadmin og Nico kan markere saken som fakturert/trukket.',
              style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.onMarkInvoiced!();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Marker som fakturert'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lockBanner(PartnerDeductionCase c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.isDeleted
                  ? 'Saken er slettet og permanent arkivert.'
                  : 'Fakturert og låst — kan ikke endres.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deletionAudit(PartnerDeductionCase c, DateFormat df) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slettet av ${c.deletedByName ?? 'ukjent'}',
            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.red.shade800),
          ),
          if (c.deletedAt != null)
            Text('${df.format(c.deletedAt!)}', style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
          if (c.deletionComment?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('«${c.deletionComment}»', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  List<Widget> _sakTab(PartnerDeductionCase c, NumberFormat money, DateFormat df) {
    final editable = c.isEditable;
    return [
      Row(
        children: [
          Text(money.format(c.amountNok), style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: DriftProTheme.error,
          )),
          const Spacer(),
          Chip(label: Text(
            c.isDeleted
                ? 'Slettet'
                : c.isLocked
                    ? 'Låst'
                    : c.isInvoiced
                        ? 'Fakturert'
                        : 'Åpen',
          )),
        ],
      ),
      const SizedBox(height: 8),
      Text(c.templateTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
      Text(c.shortDescription, style: TextStyle(color: PartnerModernUi.muted(context), height: 1.4)),
      if (c.comment?.isNotEmpty == true) ...[
        const SizedBox(height: 8),
        Text('«${c.comment}»', style: const TextStyle(fontStyle: FontStyle.italic)),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _meta('Opprettet', df.format(c.createdAt)),
          if (c.createdByName != null) _meta('Av', c.createdByName!),
          if (c.smsSent) _meta('SMS', 'Sendt'),
          if (c.emailSent) _meta('E-post', 'Sendt'),
          if (c.invoicedAt != null) _meta('Fakturert', df.format(c.invoicedAt!)),
        ],
      ),
      if (c.hasLogiqrmaRef) ...[
        const SizedBox(height: 16),
        PartnerDeductionLogiqRmaInfo(caseRow: c),
        const SizedBox(height: 16),
      ] else
        const SizedBox(height: 16),
      const Text('Bevis', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      PartnerDeductionEvidenceGallery(key: ValueKey(_galleryKey), caseId: c.id),
      const SizedBox(height: 12),
      if (editable)
        OutlinedButton.icon(
          onPressed: _busy ? null : _addEvidence,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Legg til bevis'),
        ),
      if (editable) ...[
        const SizedBox(height: 16),
        const Text('Varsle bedrift', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || widget.partner.phone?.isEmpty != false
                    ? null
                    : () => _resend(sms: true, email: false),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Send SMS'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || widget.partner.email?.isEmpty != false
                    ? null
                    : () => _resend(sms: false, email: true),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Send e-post'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _resend(sms: false, email: false, push: true),
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Send push-varsel'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : () => _resend(sms: true, email: true, push: true),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.notifications_active_outlined),
          label: const Text('Send SMS + e-post + push'),
        ),
      ],
    ];
  }

  Widget _meta(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 11)),
    );
  }
}
