import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'partner_driver_deviation_service.dart';

/// Lokal kø for sjåføravvik — lagres offline og synkes når nett er tilbake.
class PartnerDriverDeviationOfflineQueue {
  PartnerDriverDeviationOfflineQueue._();

  static const _boxName = 'partner_driver_deviation_outbox_v1';
  static Box<String>? _box;
  static const _uuid = Uuid();

  static Future<void> init() async {
    if (_box != null) return;
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  static Future<Box<String>> _ensureBox() async {
    if (_box == null) await init();
    return _box!;
  }

  static int get pendingCount => _box?.length ?? 0;

  static Future<bool> isOnline() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.any((x) => x != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  static Future<String> enqueue({
    required String companyId,
    required String partnerId,
    required String partnerVehicleId,
    required DateTime routeDate,
    required String customerName,
    required String freightUnit,
    required String customerRef,
    required String comment,
    String? orderRef,
    String? customerPhone,
    String? routeShareId,
    String? reporterName,
    List<PartnerDriverDeviationMedia> images = const [],
    List<PartnerDriverDeviationMedia> videos = const [],
  }) async {
    final box = await _ensureBox();
    final id = _uuid.v4();
    final entry = <String, dynamic>{
      'id': id,
      'company_id': companyId,
      'partner_id': partnerId,
      'partner_vehicle_id': partnerVehicleId,
      'route_share_id': routeShareId,
      'route_date': routeDate.toIso8601String().split('T').first,
      'customer_name': customerName,
      'freight_unit': freightUnit,
      'customer_ref': customerRef,
      'order_ref': orderRef,
      'customer_phone': customerPhone,
      'comment': comment,
      'reporter_name': reporterName,
      'images': [
        for (final m in images)
          {
            'name': m.name,
            'bytes_b64': base64Encode(m.bytes),
          },
      ],
      'videos': [
        for (final m in videos)
          {
            'name': m.name,
            'bytes_b64': base64Encode(m.bytes),
          },
      ],
      'created_at': DateTime.now().toIso8601String(),
    };
    await box.put(id, jsonEncode(entry));
    return id;
  }

  static Future<List<Map<String, dynamic>>> peekAll() async {
    final box = await _ensureBox();
    final out = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    out.sort((a, b) {
      final aa = a['created_at']?.toString() ?? '';
      final bb = b['created_at']?.toString() ?? '';
      return aa.compareTo(bb);
    });
    return out;
  }

  static Future<int> flushPending() async {
    if (!await isOnline()) return 0;
    final box = await _ensureBox();
    var synced = 0;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final images = _mediaList(map['images']);
        final videos = _mediaList(map['videos']);
        final day = DateTime.tryParse(map['route_date']?.toString() ?? '') ??
            DateTime.now();
        await PartnerDriverDeviationService.create(
          companyId: map['company_id'] as String,
          partnerId: map['partner_id'] as String,
          partnerVehicleId: map['partner_vehicle_id'] as String,
          routeDate: day,
          routeShareId: map['route_share_id'] as String?,
          customerName: map['customer_name'] as String? ?? '',
          freightUnit: map['freight_unit'] as String? ?? '',
          customerRef: map['customer_ref'] as String? ?? '',
          orderRef: map['order_ref'] as String?,
          customerPhone: map['customer_phone'] as String?,
          comment: map['comment'] as String? ?? '',
          reporterName: map['reporter_name'] as String?,
          images: images,
          videos: videos,
        );
        await box.delete(key);
        synced++;
      } catch (_) {
        // Behold i kø — prøv neste runde.
      }
    }
    return synced;
  }

  static List<PartnerDriverDeviationMedia> _mediaList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PartnerDriverDeviationMedia>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? 'fil.bin';
      final b64 = item['bytes_b64']?.toString();
      if (b64 == null || b64.isEmpty) continue;
      try {
        out.add(
          PartnerDriverDeviationMedia(
            name: name,
            bytes: Uint8List.fromList(base64Decode(b64)),
          ),
        );
      } catch (_) {}
    }
    return out;
  }
}
