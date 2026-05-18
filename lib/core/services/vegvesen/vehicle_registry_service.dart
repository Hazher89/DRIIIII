import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

/// Resultat fra Vegvesen / edge function `vehicle-lookup`.
class VehicleRegistryLookup {
  final String registrationNumber;
  final int? modelYear;
  final int? payloadKg;
  final DateTime? euLastAt;
  final DateTime? euNextAt;
  final String? make;
  final String? model;
  final Map<String, dynamic>? raw;

  const VehicleRegistryLookup({
    required this.registrationNumber,
    this.modelYear,
    this.payloadKg,
    this.euLastAt,
    this.euNextAt,
    this.make,
    this.model,
    this.raw,
  });

  factory VehicleRegistryLookup.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return VehicleRegistryLookup(
      registrationNumber: json['registration_number'] as String? ?? '',
      modelYear: json['model_year'] as int?,
      payloadKg: json['payload_kg'] as int?,
      euLastAt: parseDate(json['eu_last_at']),
      euNextAt: parseDate(json['eu_next_at']),
      make: json['make'] as String?,
      model: json['model'] as String?,
      raw: json['raw'] as Map<String, dynamic>?,
    );
  }

  bool get isConfigured => raw != null || modelYear != null || euNextAt != null;
}

class VehicleRegistryService {
  VehicleRegistryService._();

  static bool get _ok =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  /// Henter tekniske data fra Vegvesen via Supabase Edge Function.
  /// Krever `VEGVESEN_API_KEY` i prosjekt-secrets og deploy av `vehicle-lookup`.
  static Future<VehicleRegistryLookup?> lookup(String registrationNumber) async {
    if (!_ok) return null;
    final plate = registrationNumber.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (plate.length < 2) return null;

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'vehicle-lookup',
        body: {'registration_number': plate},
      );
      if (res.status != 200) {
        final data = res.data;
        if (data is Map && data['configured'] == false) return null;
        throw Exception(
          data is Map ? (data['error'] ?? 'Oppslag feilet') : 'Oppslag feilet',
        );
      }
      final data = res.data;
      if (data is! Map<String, dynamic>) return null;
      return VehicleRegistryLookup.fromJson(data);
    } catch (e) {
      rethrow;
    }
  }
}
