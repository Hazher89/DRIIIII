import 'dart:typed_data';

import '../../../core/permissions/user_access.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_summary_meta.dart';
import '../../../models/user_profile.dart';
import 'partner_service.dart';
import 'partner_summary_matcher.dart';
import 'partner_summary_parser.dart';

class SummaryDispatchDraft {
  SummaryDispatchDraft({
    required this.localId,
    required this.fileName,
    required this.bytes,
    required this.parsed,
    this.partnerId,
    this.matchReason,
    this.matchScore = 0,
    this.selected = true,
    String? weekLabel,
  }) : weekLabel = weekLabel ?? parsed.weekLabel;

  final String localId;
  final String fileName;
  final Uint8List bytes;
  final PartnerSummaryMeta parsed;
  String? partnerId;
  String? matchReason;
  int matchScore;
  bool selected;
  String weekLabel;

  PartnerSummaryMeta get effectiveMeta => PartnerSummaryMeta(
        weekLabel: weekLabel,
        invoiceDate: parsed.invoiceDate,
        paymentDate: parsed.paymentDate,
        companyNameRaw: parsed.companyNameRaw,
        vehicles: parsed.vehicles,
        sourceFileName: fileName,
      );

  bool get needsReview => partnerId == null || matchScore < 70;
}

class SummarySendResult {
  const SummarySendResult({
    required this.sent,
    required this.skipped,
    required this.errors,
  });

  final int sent;
  final int skipped;
  final List<String> errors;
}

class PartnerSummaryService {
  PartnerSummaryService._();

  static List<SummaryDispatchDraft> buildDrafts({
    required List<({String name, Uint8List bytes})> files,
    required List<Partner> partners,
    required Map<String, List<PartnerVehicle>> vehiclesByPartner,
  }) {
    final out = <SummaryDispatchDraft>[];
    var i = 0;
    for (final file in files) {
      final parsed = PartnerSummaryParser.parse(file.bytes, fileName: file.name);
      if (parsed == null) {
        out.add(
          SummaryDispatchDraft(
            localId: 'draft_${i++}',
            fileName: file.name,
            bytes: file.bytes,
            parsed: PartnerSummaryMeta(
              weekLabel: '—',
              companyNameRaw: file.name,
              vehicles: const [],
              sourceFileName: file.name,
            ),
            selected: false,
            matchReason: 'Kunne ikke lese PDF — velg bedrift manuelt',
          ),
        );
        continue;
      }

      final match = PartnerSummaryMatcher.bestMatch(
        summary: parsed,
        partners: partners,
        vehiclesByPartner: vehiclesByPartner,
      );

      out.add(
        SummaryDispatchDraft(
          localId: 'draft_${i++}',
          fileName: file.name,
          bytes: file.bytes,
          parsed: parsed,
          partnerId: match?.partner.id,
          matchReason: match?.reason,
          matchScore: match?.score ?? 0,
          selected: match != null && match.score >= 50,
        ),
      );
    }
    return out;
  }

  static Future<SummarySendResult> sendSelected({
    required String companyId,
    required List<SummaryDispatchDraft> drafts,
    required List<Partner> partners,
    required bool sendSms,
  }) async {
    var sent = 0;
    var skipped = 0;
    final errors = <String>[];

    final partnerById = {for (final p in partners) p.id: p};
    final usedPartnerIds = <String>{};

    for (final draft in drafts) {
      if (!draft.selected) {
        skipped++;
        continue;
      }
      final partnerId = draft.partnerId;
      if (partnerId == null) {
        errors.add('${draft.fileName}: mangler bedrift');
        skipped++;
        continue;
      }
      if (usedPartnerIds.contains(partnerId)) {
        errors.add('${draft.fileName}: bedrift allerede tildelt i denne sendingen');
        skipped++;
        continue;
      }

      final partner = partnerById[partnerId];
      if (partner == null) {
        errors.add('${draft.fileName}: ugyldig bedrift');
        skipped++;
        continue;
      }

      try {
        await _deliverOne(
          companyId: companyId,
          partner: partner,
          draft: draft,
          sendSms: sendSms,
        );
        usedPartnerIds.add(partnerId);
        sent++;
      } catch (e) {
        errors.add('${draft.fileName}: $e');
        skipped++;
      }
    }

    if (sendSms && sent > 0) {
      await PartnerService.flushSmsOutbox();
    }

    return SummarySendResult(sent: sent, skipped: skipped, errors: errors);
  }

  static Future<void> _deliverOne({
    required String companyId,
    required Partner partner,
    required SummaryDispatchDraft draft,
    required bool sendSms,
  }) async {
    final meta = draft.effectiveMeta;
    final safeName = draft.fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'company_$companyId/partner_summaries/${partner.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final storedPath = await PartnerService.uploadPartnerDocumentPdf(
      storagePath: storagePath,
      bytes: draft.bytes,
    );

    final title = 'Oppsummering uke ${meta.weekLabel}';

    await PartnerService.addDocument(
      PartnerDocument(
        id: '',
        partnerId: partner.id,
        companyId: companyId,
        title: title,
        storagePath: storedPath,
        fileName: draft.fileName,
        mimeType: 'application/pdf',
        description: meta.toJsonString(),
        docCategory: 'summary',
        documentType: 'okonomi',
        ownerVisible: true,
        driverVisible: false,
        createdAt: DateTime.now(),
      ),
    );

    if (sendSms) {
      final phone = partner.phone?.trim();
      if (phone != null && phone.length >= 8) {
        final amount = PartnerSummaryMeta.formatAmount(meta.transportTotalExVat);
        final pay = PartnerSummaryMeta.formatDate(meta.paymentDate);
        final msg =
            'Ny oppsummering uke ${meta.weekLabel} er tilgjengelig i bil-eier portalen. '
            'Transport eks mva: $amount kr. Betaling: $pay.';
        final sms = await PartnerService.queuePartnerComposeSms(
          companyId: companyId,
          phone: phone,
          message: msg,
        );
        if (!sms.success) {
          throw StateError('Dokument lagret, men SMS feilet: ${sms.error}');
        }
      }
    }
  }

  static bool canManage(UserProfile? profile) {
    if (profile == null) return false;
    return profile.isSuperAdmin;
  }
}
