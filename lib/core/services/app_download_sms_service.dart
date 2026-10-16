import 'package:supabase_flutter/supabase_flutter.dart';

/// Result from [AppDownloadSmsService.send].
class AppDownloadSmsResult {
  const AppDownloadSmsResult({
    required this.smsId,
    required this.platform,
    this.code,
    this.redeemUrl,
    this.remainingCodes,
    this.toPhone,
  });

  final String smsId;
  final String platform;
  final String? code;
  final String? redeemUrl;
  final int? remainingCodes;
  final String? toPhone;

  factory AppDownloadSmsResult.fromJson(Map<String, dynamic> json) {
    return AppDownloadSmsResult(
      smsId: json['sms_id']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      code: json['code']?.toString(),
      redeemUrl: json['redeem_url']?.toString(),
      remainingCodes: (json['remaining_codes'] as num?)?.toInt(),
      toPhone: json['to_phone']?.toString(),
    );
  }
}

/// Queue Apple (unique redeem) or Google Play download SMS via RPC.
class AppDownloadSmsService {
  AppDownloadSmsService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<int> remainingCodes() async {
    final data = await _client.rpc('app_store_redeem_codes_stats');
    if (data is Map) {
      return (data['available'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  static Future<({int available, int used})> stats() async {
    final data = await _client.rpc('app_store_redeem_codes_stats');
    if (data is Map) {
      return (
        available: (data['available'] as num?)?.toInt() ?? 0,
        used: (data['used'] as num?)?.toInt() ?? 0,
      );
    }
    return (available: 0, used: 0);
  }

  static Future<AppDownloadSmsResult> send({
    required String platform,
    required String phone,
    String? displayName,
    String? username,
    String? password,
    String? refType,
    String? refId,
    String? userId,
    String? companyId,
  }) async {
    final data = await _client.rpc('send_app_download_sms', params: {
      'p_platform': platform,
      'p_phone': phone,
      'p_display_name': displayName,
      'p_username': username,
      'p_password': password,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_user_id': userId,
      'p_company_id':
          companyId ?? '00000000-0000-0000-0000-000000000000',
    });
    if (data is! Map) {
      throw Exception('Uventet svar fra send_app_download_sms');
    }
    return AppDownloadSmsResult.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<AppDownloadSmsResult> sendApple({
    required String phone,
    String? displayName,
    String? username,
    String? password,
    String? refType,
    String? refId,
    String? userId,
    String? companyId,
  }) =>
      send(
        platform: 'apple',
        phone: phone,
        displayName: displayName,
        username: username,
        password: password,
        refType: refType,
        refId: refId,
        userId: userId,
        companyId: companyId,
      );

  static Future<AppDownloadSmsResult> sendGoogle({
    required String phone,
    String? displayName,
    String? username,
    String? password,
    String? refType,
    String? refId,
    String? userId,
    String? companyId,
  }) =>
      send(
        platform: 'google',
        phone: phone,
        displayName: displayName,
        username: username,
        password: password,
        refType: refType,
        refId: refId,
        userId: userId,
        companyId: companyId,
      );
}
