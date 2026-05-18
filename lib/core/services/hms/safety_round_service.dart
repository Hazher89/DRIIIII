import 'dart:typed_data';

import '../../../models/safety_round.dart';
import '../supabase_service.dart';
import 'equipment_service.dart';
import 'safety_round_pdf.dart';

class SafetyRoundService {
  SafetyRoundService._();

  static Future<List<SafetyRound>> fetchAll({
    required String companyId,
    String? search,
  }) async {
    var q = SupabaseService.client
        .from('safety_rounds')
        .select()
        .eq('company_id', companyId);
    final data = await q.order('completed_at', ascending: false);
    var list = (data as List)
        .map((e) => SafetyRound.fromJson(e as Map<String, dynamic>))
        .toList();
    if (search != null && search.trim().isNotEmpty) {
      final qLower = search.toLowerCase();
      list = list.where((r) {
        return r.title.toLowerCase().contains(qLower) ||
            (r.archiveNumber?.toLowerCase().contains(qLower) ?? false) ||
            (r.location?.toLowerCase().contains(qLower) ?? false) ||
            (r.conductorName?.toLowerCase().contains(qLower) ?? false);
      }).toList();
    }
    return list;
  }

  static Future<SafetyRound?> fetchById(String id) async {
    final row = await SupabaseService.client
        .from('safety_rounds')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return SafetyRound.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<SafetyRound> save(SafetyRound round, {String? id}) async {
    var payload = Map<String, dynamic>.from(round.toInsertJson());
    const optionalKeys = [
      'template_id',
      'location',
      'archive_number',
      'pdf_url',
      'next_round_date',
      'image_urls',
    ];
    for (;;) {
      try {
        return await _persist(payload, id: id);
      } catch (e) {
        final msg = e.toString();
        String? drop;
        for (final k in optionalKeys) {
          if (payload.containsKey(k) && msg.contains(k)) {
            drop = k;
            break;
          }
        }
        if (drop == null) rethrow;
        payload.remove(drop);
      }
    }
  }

  static Future<SafetyRound> _persist(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    if (id != null && id.isNotEmpty) {
      final row = await SupabaseService.client
          .from('safety_rounds')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      return SafetyRound.fromJson(row);
    }
    final row = await SupabaseService.client
        .from('safety_rounds')
        .insert(payload)
        .select()
        .single();
    return SafetyRound.fromJson(row);
  }

  static Future<String> uploadPdf({
    required String companyId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    return EquipmentService.uploadDocument(
      companyId: companyId,
      fileName: fileName,
      bytes: bytes,
      subfolder: 'vernerunder',
    );
  }

  static Future<SafetyRound> finalizeWithPdf(SafetyRound round) async {
    try {
      final bytes = await SafetyRoundPdfGenerator.generate(round);
      final name =
          'vernerunde_${round.archiveNumber ?? round.id.substring(0, 8)}.pdf';
      final url = await uploadPdf(
        companyId: round.companyId,
        fileName: name,
        bytes: bytes,
      );
      return save(
        round.copyWith(pdfUrl: url),
        id: round.id,
      );
    } catch (_) {
      return round;
    }
  }
}
