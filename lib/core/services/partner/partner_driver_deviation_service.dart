import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../models/partner/partner_driver_deviation.dart';
import '../storage/company_file_storage.dart';
import '../storage/storage_file_access.dart';
import '../supabase_service.dart';

class PartnerDriverDeviationMedia {
  const PartnerDriverDeviationMedia({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class PartnerDriverDeviationService {
  static const _uuid = Uuid();

  static Future<PartnerDriverDeviation> create({
    required String companyId,
    required String partnerId,
    required String partnerVehicleId,
    required DateTime routeDate,
    required String customerName,
    required String freightUnit,
    required String customerRef,
    required String comment,
    String? orderRef,
    String? routeShareId,
    String? reporterName,
    List<PartnerDriverDeviationMedia> images = const [],
    List<PartnerDriverDeviationMedia> videos = const [],
  }) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw StateError('Du må være innlogget.');

    final id = _uuid.v4();
    final imageUrls = await _uploadMedia(
      companyId: companyId,
      partnerId: partnerId,
      deviationId: id,
      mediaType: 'images',
      files: images,
    );
    final videoUrls = await _uploadMedia(
      companyId: companyId,
      partnerId: partnerId,
      deviationId: id,
      mediaType: 'videos',
      files: videos,
    );

    final row = await SupabaseService.client
        .from('partner_driver_deviations')
        .insert({
          'id': id,
          'company_id': companyId,
          'partner_id': partnerId,
          'partner_vehicle_id': partnerVehicleId,
          'route_share_id': routeShareId,
          'reported_by': userId,
          'reporter_name': _nullable(reporterName),
          'route_date': _date(routeDate),
          'customer_name': customerName.trim(),
          'freight_unit': freightUnit.trim(),
          'customer_ref': customerRef.trim(),
          'order_ref': _nullable(orderRef),
          'comment': comment.trim(),
          'image_urls': imageUrls,
          'video_urls': videoUrls,
        })
        .select()
        .single();
    return PartnerDriverDeviation.fromJson(row);
  }

  static Future<List<String>> _uploadMedia({
    required String companyId,
    required String partnerId,
    required String deviationId,
    required String mediaType,
    required List<PartnerDriverDeviationMedia> files,
  }) async {
    final refs = <String>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final path =
          '$companyId/partners/$partnerId/driver_deviations/$deviationId/'
          '$mediaType/${DateTime.now().microsecondsSinceEpoch}_$i-${file.name}';
      final stored = await CompanyFileStorage.upload(
        supabaseBucket: 'documents',
        storagePath: path,
        bytes: file.bytes,
        category: 'partner_driver_deviation',
        fileName: file.name,
      );
      refs.add(CompanyFileStorage.toStorageReference(stored));
    }
    return refs;
  }

  /// «Mine» for sjåfør/ansatt = egne. For bil-eier: [firmWide] + [partnerId]
  /// = alle avvik i partnerfirmaet.
  static Future<List<PartnerDriverDeviation>> listMine({
    required String companyId,
    String? partnerId,
    bool firmWide = false,
    int limit = 50,
  }) async {
    if (firmWide && partnerId != null && partnerId.isNotEmpty) {
      return list(
        companyId: companyId,
        partnerId: partnerId,
        limit: limit,
      );
    }
    final uid = SupabaseService.currentUser?.id;
    final all = await list(
      companyId: companyId,
      partnerId: partnerId,
      limit: limit,
    );
    if (uid == null) return all;
    return all
        .where((d) => d.reportedBy == uid)
        .toList(growable: false);
  }

  static Future<List<PartnerDriverDeviation>> list({
    required String companyId,
    String? partnerId,
    String? query,
    int limit = 50,
  }) async {
    final rows =
        await SupabaseService.client.rpc(
              'list_partner_driver_deviations',
              params: {
                'p_company_id': companyId,
                'p_query': _nullable(query),
                'p_limit': limit,
                'p_partner_id': partnerId,
              },
            )
            as List<dynamic>?;
    var items = (rows ?? const [])
        .map(
          (row) => PartnerDriverDeviation.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    // Ekstra sikkerhet i klient: partnerportal skal aldri vise andre firma.
    if (partnerId != null && partnerId.isNotEmpty) {
      items = items
          .where((d) => d.partnerId == partnerId)
          .toList(growable: false);
    }
    return items;
  }

  static Future<List<PartnerDriverDeviation>> search({
    required String companyId,
    required String query,
    String? partnerId,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final rows =
        await SupabaseService.client.rpc(
              'search_partner_driver_deviations',
              params: {
                'p_company_id': companyId,
                'p_query': q,
                'p_partner_id': partnerId,
              },
            )
            as List<dynamic>?;
    var items = (rows ?? const [])
        .map(
          (row) => PartnerDriverDeviation.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    if (partnerId != null && partnerId.isNotEmpty) {
      items = items
          .where((d) => d.partnerId == partnerId)
          .toList(growable: false);
    }
    return items;
  }

  static Future<PartnerDriverDeviationAlertSettings> loadAlertSettings(
    String companyId,
  ) async {
    final row = await SupabaseService.client
        .from('partner_driver_deviation_alert_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) {
      return PartnerDriverDeviationAlertSettings(companyId: companyId);
    }
    return PartnerDriverDeviationAlertSettings.fromJson(row);
  }

  static Future<void> saveAlertSettings(
    PartnerDriverDeviationAlertSettings settings,
  ) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw StateError('Du må være innlogget.');
    await SupabaseService.client
        .from('partner_driver_deviation_alert_settings')
        .upsert({
          'company_id': settings.companyId,
          'enabled': settings.enabled,
          'emails': settings.emails,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': userId,
        });
  }

  static Future<String> resolveMediaUrl(String reference) {
    return StorageFileAccess.resolveViewUrl(reference);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _nullable(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
