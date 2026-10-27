import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

/// Offentlig CCC/butikk-søk på sjåføravvik (uten innlogging).
class PublicDriverDeviationHit {
  const PublicDriverDeviationHit({
    required this.id,
    required this.comment,
    required this.routeDate,
    required this.createdAt,
    required this.status,
    required this.images,
    required this.videos,
    this.customerName,
    this.freightUnit,
    this.customerRef,
    this.orderRef,
    this.customerPhone,
    this.reporterName,
    this.mediaIncomplete = false,
  });

  final String id;
  final String? customerName;
  final String? freightUnit;
  final String? customerRef;
  final String? orderRef;
  final String? customerPhone;
  final String comment;
  final DateTime routeDate;
  final DateTime createdAt;
  final String status;
  final String? reporterName;
  final List<String> images;
  final List<String> videos;
  final bool mediaIncomplete;

  int get mediaCount => images.length + videos.length;

  String get title {
    final name = customerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final bilag = orderRef?.trim();
    if (bilag != null && bilag.isNotEmpty) return 'Ordre $bilag';
    final fu = freightUnit?.trim() ?? customerRef?.trim();
    if (fu != null && fu.isNotEmpty) return 'Nr $fu';
    return 'Leveringsavvik';
  }

  factory PublicDriverDeviationHit.fromJson(Map<String, dynamic> json) {
    DateTime parseDay(dynamic v) {
      final s = v?.toString() ?? '';
      return DateTime.tryParse(s) ?? DateTime.now();
    }

    List<String> urls(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }

    return PublicDriverDeviationHit(
      id: json['id'] as String,
      customerName: json['customer_name'] as String?,
      freightUnit: json['freight_unit'] as String?,
      customerRef: json['customer_ref'] as String?,
      orderRef: json['order_ref'] as String?,
      customerPhone: json['customer_phone'] as String?,
      comment: (json['comment'] as String?)?.trim() ?? '',
      routeDate: parseDay(json['route_date']),
      createdAt: parseDay(json['created_at']),
      status: json['status'] as String? ?? 'open',
      reporterName: json['reporter_name'] as String?,
      images: urls(json['images']),
      videos: urls(json['videos']),
      mediaIncomplete: json['media_incomplete'] == true,
    );
  }
}

class PublicDriverDeviationService {
  PublicDriverDeviationService._();

  static Future<({List<PublicDriverDeviationHit> items, String? hint})> search(
    String query,
  ) async {
    final q = query.trim();
    if (q.length < 3) {
      return (
        items: const <PublicDriverDeviationHit>[],
        hint:
            'Skriv kundenavn, telefon, ordre (21/22/60) eller nr (39/41).',
      );
    }
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Appen er ikke koblet til server.');
    }

    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'public-driver-deviation-lookup',
      body: {'query': q},
    );
    final data = res.data;
    if (data is! Map) {
      throw StateError('Ugyldig svar fra server');
    }
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    final raw = data['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map(
              (e) => PublicDriverDeviationHit.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(growable: false)
        : const <PublicDriverDeviationHit>[];
    final hint = data['hint']?.toString();
    return (items: items, hint: hint);
  }
}
