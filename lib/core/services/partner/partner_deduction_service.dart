import 'dart:typed_data';

import '../../../core/constants/partner_deduction_templates.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../../../models/partner/partner_deduction_evidence.dart';
import '../../../models/partner/partner_deduction_stats.dart';
import '../storage/company_file_storage.dart';
import '../supabase_service.dart';
import 'partner_service.dart';

class PartnerDeductionPendingEvidence {
  const PartnerDeductionPendingEvidence({
    required this.fileName,
    required this.bytes,
    this.extension,
  });

  final String fileName;
  final Uint8List bytes;
  final String? extension;
}

class PartnerDeductionCreateResult {
  const PartnerDeductionCreateResult({
    required this.success,
    this.caseRow,
    this.error,
  });

  final bool success;
  final PartnerDeductionCase? caseRow;
  final String? error;
}

abstract final class PartnerDeductionService {
  static bool isVideoFileName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return {'mp4', 'mov', 'webm', 'm4v', 'avi', 'mkv'}.contains(ext);
  }

  static Future<PartnerDeductionStats> fetchStats(String companyId) async {
    final rows = await SupabaseService.client.rpc(
      'get_partner_deduction_stats',
      params: {'p_company_id': companyId},
    ) as List<dynamic>?;
    final row = rows?.isNotEmpty == true
        ? rows!.first as Map<String, dynamic>
        : <String, dynamic>{};
    return PartnerDeductionStats.fromJson(row);
  }

  static Future<void> flushOutbox() => PartnerService.flushSmsOutbox();

  static Future<PartnerDeductionCase> resendNotification({
    required String caseId,
    bool notifySms = true,
    bool notifyEmail = true,
  }) async {
    final row = await SupabaseService.client.rpc(
      'resend_partner_deduction_notification',
      params: {
        'p_case_id': caseId,
        'p_notify_sms': notifySms,
        'p_notify_email': notifyEmail,
      },
    ) as Map<String, dynamic>;
    return PartnerDeductionCase.fromJson(row);
  }

  static Future<List<PartnerDeductionCase>> listCasesPortal({
    required String partnerId,
    int limit = 100,
  }) async {
    final rows = await SupabaseService.client.rpc(
      'list_partner_deduction_cases_portal',
      params: {
        'p_partner_id': partnerId,
        'p_limit': limit,
      },
    ) as List<dynamic>?;

    return (rows ?? [])
        .map((e) => PartnerDeductionCase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<PartnerDeductionEvidence>> listEvidence(String caseId) async {
    final rows = await SupabaseService.client.rpc(
      'list_partner_deduction_evidence',
      params: {'p_case_id': caseId},
    ) as List<dynamic>?;

    return (rows ?? [])
        .map((e) => PartnerDeductionEvidence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<PartnerDeductionEvidence> uploadEvidence({
    required String companyId,
    required String partnerId,
    required String caseId,
    required String caseNumber,
    required PartnerDeductionPendingEvidence file,
  }) async {
    final isVideo = isVideoFileName(file.fileName);
    final storagePath =
        '$companyId/partners/$partnerId/deductions/$caseId/${DateTime.now().millisecondsSinceEpoch}_${file.fileName}';

    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: storagePath,
      bytes: file.bytes,
      category: 'partner_deductions',
      fileName: '${caseNumber}_${file.fileName}',
    );

    final ref = CompanyFileStorage.toStorageReference(stored);
    final row = await SupabaseService.client.rpc(
      'add_partner_deduction_evidence',
      params: {
        'p_case_id': caseId,
        'p_storage_ref': ref,
        'p_storage_provider': stored.isDropbox ? 'dropbox' : 'supabase',
        'p_file_name': file.fileName,
        'p_mime_type': _mimeForExtension(file.extension ?? file.fileName),
        'p_media_type': isVideo ? 'video' : 'image',
        'p_file_size_bytes': file.bytes.length,
        'p_dropbox_path': stored.isDropbox ? stored.path : null,
      },
    ) as Map<String, dynamic>;

    return PartnerDeductionEvidence.fromJson(row);
  }

  static Future<List<PartnerDeductionEvidence>> uploadEvidenceBatch({
    required String companyId,
    required String partnerId,
    required String caseId,
    required String caseNumber,
    required List<PartnerDeductionPendingEvidence> files,
  }) async {
    final out = <PartnerDeductionEvidence>[];
    for (final f in files) {
      out.add(await uploadEvidence(
        companyId: companyId,
        partnerId: partnerId,
        caseId: caseId,
        caseNumber: caseNumber,
        file: f,
      ));
    }
    return out;
  }

  static String? _mimeForExtension(String nameOrExt) {
    final ext = nameOrExt.contains('.')
        ? nameOrExt.split('.').last.toLowerCase()
        : nameOrExt.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      _ => null,
    };
  }

  static Future<List<PartnerDeductionCase>> listCases({
    required String companyId,
    String? status,
    String? partnerId,
    int limit = 200,
  }) async {
    final rows = await SupabaseService.client.rpc(
      'list_partner_deduction_cases',
      params: {
        'p_company_id': companyId,
        'p_status': status,
        'p_partner_id': partnerId,
        'p_limit': limit,
        'p_offset': 0,
      },
    ) as List<dynamic>?;

    return (rows ?? [])
        .map((e) => PartnerDeductionCase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String buildSmsBody({
    required Partner partner,
    required PartnerDeductionTemplate template,
    required double amountNok,
    String? comment,
    String? logiqrmaCaseNumber,
    String? voucherNumber,
    String? logiqrmaComment,
  }) {
    final amount = amountNok.toStringAsFixed(0);
    final extra = (comment ?? '').trim();
    final suffix = extra.isEmpty ? '' : ' Merknad: $extra';
    final logiqrma = _logiqrmaNotice(
      caseNumber: logiqrmaCaseNumber,
      voucherNumber: voucherNumber,
      comment: logiqrmaComment,
      compact: true,
    );
    return 'Hei ${partner.name}. MAVI Logistikk registrerer trekk på kr $amount,- '
        'vedr. ${template.title} (sak {sak}). '
        '${template.shortDescription}$suffix$logiqrma '
        'Kontakt oss ved spørsmål. Mvh MAVI Logistikk';
  }

  static String buildEmailSubject({required Partner partner}) {
    return 'Trekk registrert — sak {sak} — ${partner.name}';
  }

  static String buildEmailBody({
    required Partner partner,
    required PartnerDeductionTemplate template,
    required double amountNok,
    String? comment,
    String? logiqrmaCaseNumber,
    String? voucherNumber,
    String? logiqrmaComment,
  }) {
    final amount = amountNok.toStringAsFixed(0);
    final extra = (comment ?? '').trim();
    final logiqrma = _logiqrmaNotice(
      caseNumber: logiqrmaCaseNumber,
      voucherNumber: voucherNumber,
      comment: logiqrmaComment,
    );
    return '''
Hei ${partner.name},

MAVI Logistikk AS har registrert følgende trekk mot deres samarbeidsavtale:

Saksnummer: {sak}
Kategori: ${template.title}
Beløp: kr $amount,-

Beskrivelse:
${template.detailParagraph}

${extra.isNotEmpty ? 'Intern merknad fra MAVI:\n$extra\n\n' : ''}${logiqrma.isNotEmpty ? '$logiqrma\n' : ''}Trekket faktureres i henhold til gjeldende avtale. Ta kontakt dersom dere har spørsmål eller dokumentasjon som kan endre vurderingen.

Med vennlig hilsen
MAVI Logistikk AS
''';
  }

  static String _logiqrmaNotice({
    String? caseNumber,
    String? voucherNumber,
    String? comment,
    bool compact = false,
  }) {
    final parts = <String>[];
    if ((caseNumber ?? '').trim().isNotEmpty) {
      parts.add(compact ? ' LogiqRMA: ${caseNumber!.trim()}.' : 'LogiqRMA saksnummer: ${caseNumber!.trim()}');
    }
    if ((voucherNumber ?? '').trim().isNotEmpty) {
      parts.add(compact ? ' Bilag: ${voucherNumber!.trim()}.' : 'Bilag: ${voucherNumber!.trim()}');
    }
    if ((comment ?? '').trim().isNotEmpty) {
      parts.add(compact ? ' Kommentar: ${comment!.trim()}.' : 'LogiqRMA kommentar: ${comment!.trim()}');
    }
    if (parts.isEmpty) return '';
    if (compact) return parts.join();
    return 'LogiqRMA:\n${parts.join('\n')}\n';
  }

  static Future<PartnerDeductionCase> unlockCase(String caseId) async {
    final row = await SupabaseService.client.rpc(
      'unlock_partner_deduction_case',
      params: {'p_case_id': caseId},
    ) as Map<String, dynamic>;
    return PartnerDeductionCase.fromJson(row);
  }

  static Future<PartnerDeductionCase> softDeleteCase({
    required String caseId,
    required String deletionComment,
  }) async {
    final row = await SupabaseService.client.rpc(
      'soft_delete_partner_deduction_case',
      params: {
        'p_case_id': caseId,
        'p_deletion_comment': deletionComment,
      },
    ) as Map<String, dynamic>;
    return PartnerDeductionCase.fromJson(row);
  }

  static Future<PartnerDeductionCase> updateLogiqrma({
    required String caseId,
    String? logiqrmaCaseNumber,
    String? voucherNumber,
    String? logisticsDescription,
  }) async {
    final row = await SupabaseService.client.rpc(
      'update_partner_deduction_logiqrma',
      params: {
        'p_case_id': caseId,
        'p_logiqrma_case_number': logiqrmaCaseNumber,
        'p_voucher_number': voucherNumber,
        'p_logistics_description': logisticsDescription,
      },
    ) as Map<String, dynamic>;
    return PartnerDeductionCase.fromJson(row);
  }

  static Future<PartnerDeductionCreateResult> createCase({
    required String companyId,
    required Partner partner,
    required PartnerDeductionTemplate template,
    required double amountNok,
    String? comment,
    String? logiqrmaCaseNumber,
    String? voucherNumber,
    String? logisticsDescription,
    bool notifySms = true,
    bool notifyEmail = true,
    List<PartnerDeductionPendingEvidence> evidence = const [],
  }) async {
    try {
      final hasPhone = partner.phone?.trim().isNotEmpty ?? false;
      final hasEmail = partner.email?.trim().isNotEmpty ?? false;

      final evidenceNote = evidence.isNotEmpty
          ? '\n\nVedlagt bevis (bilde/video) er tilgjengelig i bil-eierportalen under «Trekk».'
          : '';
      final smsBody = notifySms && hasPhone
          ? '${buildSmsBody(
              partner: partner,
              template: template,
              amountNok: amountNok,
              comment: comment,
              logiqrmaCaseNumber: logiqrmaCaseNumber,
              voucherNumber: voucherNumber,
              logiqrmaComment: logisticsDescription,
            )}${evidence.isNotEmpty ? ' Bevis finnes i portalen under Trekk.' : ''}'
          : null;
      final emailBody = notifyEmail && hasEmail
          ? '${buildEmailBody(
              partner: partner,
              template: template,
              amountNok: amountNok,
              comment: comment,
              logiqrmaCaseNumber: logiqrmaCaseNumber,
              voucherNumber: voucherNumber,
              logiqrmaComment: logisticsDescription,
            )}$evidenceNote'
          : null;

      final row = await SupabaseService.client.rpc(
        'create_partner_deduction_case',
        params: {
          'p_company_id': companyId,
          'p_partner_id': partner.id,
          'p_template_id': template.id,
          'p_template_title': template.title,
          'p_short_description': template.shortDescription,
          'p_comment': comment,
          'p_amount_nok': amountNok,
          'p_notify_sms': false,
          'p_notify_email': false,
          'p_sms_body': smsBody,
          'p_email_subject': notifyEmail && hasEmail
              ? buildEmailSubject(partner: partner)
              : null,
          'p_email_body': emailBody,
          'p_logiqrma_case_number': logiqrmaCaseNumber,
          'p_voucher_number': voucherNumber,
          'p_logistics_description': logisticsDescription,
        },
      ) as Map<String, dynamic>;

      var created = PartnerDeductionCase.fromJson({
        ...row,
        'partner_name': partner.name,
      });

      if (evidence.isNotEmpty) {
        await uploadEvidenceBatch(
          companyId: companyId,
          partnerId: partner.id,
          caseId: created.id,
          caseNumber: created.caseNumber,
          files: evidence,
        );
      }

      if ((notifySms && hasPhone) || (notifyEmail && hasEmail)) {
        created = await resendNotification(
          caseId: created.id,
          notifySms: notifySms && hasPhone,
          notifyEmail: notifyEmail && hasEmail,
        );
        created = PartnerDeductionCase(
          id: created.id,
          companyId: created.companyId,
          partnerId: created.partnerId,
          partnerName: partner.name,
          caseNumber: created.caseNumber,
          templateId: created.templateId,
          templateTitle: created.templateTitle,
          shortDescription: created.shortDescription,
          comment: created.comment,
          amountNok: created.amountNok,
          status: created.status,
          createdBy: created.createdBy,
          createdByName: created.createdByName,
          createdAt: created.createdAt,
          notifiedAt: created.notifiedAt,
          smsSent: created.smsSent,
          emailSent: created.emailSent,
          invoicedAt: created.invoicedAt,
          invoicedBy: created.invoicedBy,
          invoicedByName: created.invoicedByName,
          evidenceCount: evidence.length,
          logiqrmaCaseNumber: created.logiqrmaCaseNumber,
          voucherNumber: created.voucherNumber,
          logisticsDescription: created.logisticsDescription,
          isLocked: created.isLocked,
          lockedAt: created.lockedAt,
        );
        await flushOutbox();
      }

      return PartnerDeductionCreateResult(success: true, caseRow: created);
    } catch (e) {
      return PartnerDeductionCreateResult(success: false, error: e.toString());
    }
  }

  static Future<int> markInvoiced({
    required String companyId,
    required List<String> caseIds,
  }) async {
    final count = await SupabaseService.client.rpc(
      'mark_partner_deductions_invoiced',
      params: {
        'p_company_id': companyId,
        'p_case_ids': caseIds,
      },
    );
    return (count as num?)?.toInt() ?? 0;
  }
}
