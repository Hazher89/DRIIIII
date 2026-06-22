import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/gm_storo_scan.dart';
import '../../services/supabase_service.dart';
import 'gm_storo_label_parser.dart';

enum GmStoroScanResult { success, duplicate, invalid }

class GmStoroScanOutcome {
  const GmStoroScanOutcome({
    required this.result,
    this.record,
    this.sscc,
  });

  final GmStoroScanResult result;
  final GmStoroScanRecord? record;
  final String? sscc;
}

/// Supabase-tjeneste for GM & STORO skannelapper.
class GmStoroService {
  GmStoroService._();

  static final GmStoroService instance = GmStoroService._();

  static SupabaseClient get _client => SupabaseService.client;

  Future<String?> _companyId() => SupabaseService.getCurrentCompanyId();

  String? get _userId => SupabaseService.currentUser?.id;

  Future<GmStoroBatch?> getOrCreateDraftBatch() async {
    final cid = await _companyId();
    final uid = _userId;
    if (cid == null || uid == null) return null;

    final existing = await _client
        .from('gm_storo_batches')
        .select()
        .eq('company_id', cid)
        .eq('created_by', uid)
        .eq('status', 'draft')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      return fetchBatch(existing['id'] as String);
    }

    final row = await _client
        .from('gm_storo_batches')
        .insert({
          'company_id': cid,
          'created_by': uid,
          'status': 'draft',
        })
        .select()
        .single();

    return GmStoroBatch.fromRow(row);
  }

  Future<GmStoroBatch?> fetchBatch(String batchId) async {
    final batchRow = await _client
        .from('gm_storo_batches')
        .select()
        .eq('id', batchId)
        .maybeSingle();
    if (batchRow == null) return null;

    final scans = await fetchScansForBatch(batchId);
    return GmStoroBatch.fromRow(batchRow, scans: scans);
  }

  Future<List<GmStoroScanRecord>> fetchScansForBatch(String batchId) async {
    final rows = await _client
        .from('gm_storo_scans')
        .select()
        .eq('batch_id', batchId)
        .order('scanned_at', ascending: false) as List<dynamic>;

    return rows
        .map((r) => GmStoroScanRecord.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<GmStoroBatch>> fetchSubmittedBatches({int limit = 100}) async {
    final cid = await _companyId();
    if (cid == null) return [];

    final rows = await _client
        .from('gm_storo_batches')
        .select()
        .eq('company_id', cid)
        .eq('status', 'submitted')
        .order('submitted_at', ascending: false)
        .limit(limit) as List<dynamic>;

    final batches = <GmStoroBatch>[];
    for (final raw in rows) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = map['id'] as String;
      final scans = await fetchScansForBatch(id);
      batches.add(GmStoroBatch.fromRow(map, scans: scans));
    }
    return batches;
  }

  Future<List<GmStoroBatch>> fetchMyDraftsAndRecent() async {
    final cid = await _companyId();
    final uid = _userId;
    if (cid == null || uid == null) return [];

    final rows = await _client
        .from('gm_storo_batches')
        .select()
        .eq('company_id', cid)
        .eq('created_by', uid)
        .order('updated_at', ascending: false)
        .limit(20) as List<dynamic>;

    final out = <GmStoroBatch>[];
    for (final raw in rows) {
      final map = Map<String, dynamic>.from(raw as Map);
      final scans = await fetchScansForBatch(map['id'] as String);
      out.add(GmStoroBatch.fromRow(map, scans: scans));
    }
    return out;
  }

  Future<GmStoroScanOutcome> registerScan({
    required String batchId,
    required GmStoroLabelData data,
    Set<String> localSsccKeys = const {},
  }) async {
    final cid = await _companyId();
    final uid = _userId;
    if (cid == null || uid == null || !data.hasMinimumData) {
      return const GmStoroScanOutcome(result: GmStoroScanResult.invalid);
    }

    final ssccKey = GmStoroLabelParser.normalizeSscc(data.sscc ?? data.barcodeRaw);
    if (ssccKey.length < 16) {
      return const GmStoroScanOutcome(result: GmStoroScanResult.invalid);
    }

    if (localSsccKeys.contains(ssccKey)) {
      return GmStoroScanOutcome(result: GmStoroScanResult.duplicate, sscc: ssccKey);
    }

    final existing = await _client
        .from('gm_storo_scans')
        .select('id')
        .eq('batch_id', batchId)
        .eq('sscc', ssccKey)
        .maybeSingle();

    if (existing != null) {
      return GmStoroScanOutcome(result: GmStoroScanResult.duplicate, sscc: ssccKey);
    }

    final payload = data.copyWithSscc(ssccKey).toInsertJson(
      companyId: cid,
      batchId: batchId,
      scannedBy: uid,
    );

    try {
      final row = await _client
          .from('gm_storo_scans')
          .insert(payload)
          .select()
          .single();

      final countRows = await _client
          .from('gm_storo_scans')
          .select('id')
          .eq('batch_id', batchId) as List;
      await _client.from('gm_storo_batches').update({
        'label_count': countRows.length,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', batchId);

      return GmStoroScanOutcome(
        result: GmStoroScanResult.success,
        sscc: ssccKey,
        record: GmStoroScanRecord.fromRow(row),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return GmStoroScanOutcome(result: GmStoroScanResult.duplicate, sscc: ssccKey);
      }
      rethrow;
    }
  }

  Future<bool> submitBatch(String batchId) async {
    final uid = _userId;
    if (uid == null) return false;

    final scans = await fetchScansForBatch(batchId);
    if (scans.isEmpty) return false;

    await _client.from('gm_storo_batches').update({
      'status': 'submitted',
      'submitted_at': DateTime.now().toIso8601String(),
      'label_count': scans.length,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', batchId).eq('created_by', uid).eq('status', 'draft');

    return true;
  }

  Future<void> removeScan(String scanId) async {
    await _client.from('gm_storo_scans').delete().eq('id', scanId);
  }
}

extension on GmStoroLabelData {
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
