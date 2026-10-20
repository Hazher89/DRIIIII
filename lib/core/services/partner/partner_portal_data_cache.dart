import '../../../models/partner/partner.dart';

/// Kortlivet cache for partnerportal-bundles (samme data, færre runder til Supabase).
class PartnerPortalDataCache {
  PartnerPortalDataCache._();

  static const Duration ttl = Duration(seconds: 60);

  static final Map<String, _CacheEntry> _entries = {};
  static final Map<String, Future<dynamic>> _inFlight = {};

  static T? get<T>(String key) {
    final e = _entries[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > ttl) {
      _entries.remove(key);
      return null;
    }
    return e.value is T ? e.value as T : null;
  }

  static Future<T>? inFlight<T>(String key) {
    final f = _inFlight[key];
    return f is Future<T> ? f : null;
  }

  static void put(String key, Object value) {
    _entries[key] = _CacheEntry(value, DateTime.now());
  }

  static void setInFlight(String key, Future<dynamic> future) {
    _inFlight[key] = future;
  }

  static void clearInFlight(String key) {
    _inFlight.remove(key);
  }

  static void invalidatePartner(String partnerId) {
    final prefix = 'partner:$partnerId:';
    _entries.removeWhere((k, _) => k.startsWith(prefix));
    _inFlight.removeWhere((k, _) => k.startsWith(prefix));
  }

  static void clear() {
    _entries.clear();
    _inFlight.clear();
  }

  static String ownerKey(Partner partner) => 'partner:${partner.id}:owner';

  static String driverKey(Partner partner, String? vehicleId) =>
      'partner:${partner.id}:driver:${vehicleId ?? ''}';
}

class _CacheEntry {
  _CacheEntry(this.value, this.at);
  final Object value;
  final DateTime at;
}
