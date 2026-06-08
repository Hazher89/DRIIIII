class RouteAckNudgeResult {
  final bool ok;
  final String message;
  final int routesNudged;
  final int smsQueued;
  final int emailQueued;
  final int skipped;

  const RouteAckNudgeResult({
    required this.ok,
    required this.message,
    this.routesNudged = 0,
    this.smsQueued = 0,
    this.emailQueued = 0,
    this.skipped = 0,
  });

  factory RouteAckNudgeResult.fromRpc(dynamic data) {
    if (data is! Map) {
      return const RouteAckNudgeResult(ok: false, message: 'Ugyldig svar fra server');
    }
    final m = Map<String, dynamic>.from(data);
    return RouteAckNudgeResult(
      ok: m['ok'] as bool? ?? false,
      message: (m['message'] as String?) ?? 'Ukjent svar',
      routesNudged: m['routes_nudged'] as int? ?? (m['ok'] == true ? 1 : 0),
      smsQueued: m['sms_queued'] as int? ?? 0,
      emailQueued: m['email_queued'] as int? ?? 0,
      skipped: m['skipped'] as int? ?? 0,
    );
  }
}
