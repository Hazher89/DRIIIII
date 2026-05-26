import '../../core/services/partner/route_pdf_text_service.dart';
import '../../core/services/supabase_service.dart';
import '../models/lm_order.dart';
import 'postal_geocode_service.dart';

/// Operativ ordrekø — erstatter SAP som primær inngang.
class LastMileOrderService {
  LastMileOrderService._();

  static Future<String?> _companyId() => SupabaseService.getCurrentCompanyId();

  static Future<int> countPending() async {
    final cid = await _companyId();
    if (cid == null) return 0;
    try {
      final rows = await SupabaseService.client
          .from('lm_orders')
          .select('id')
          .eq('company_id', cid)
          .eq('status', 'pending');
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<LmOrder>> fetchPending({int limit = 100}) async {
    final cid = await _companyId();
    if (cid == null) return [];
    try {
      final rows = await SupabaseService.client
          .from('lm_orders')
          .select()
          .eq('company_id', cid)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List).map((e) => LmOrder.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<LmOrder>> fetchByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final cid = await _companyId();
    if (cid == null) return [];
    final rows = await SupabaseService.client
        .from('lm_orders')
        .select()
        .eq('company_id', cid)
        .inFilter('id', ids);
    return (rows as List).map((e) => LmOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<LmOrder?> create(LmOrder draft) async {
    final cid = await _companyId();
    if (cid == null) return null;

    var lat = draft.lat;
    var lng = draft.lng;
    if (lat == null || lng == null) {
      final geo = await PostalGeocodeService.resolve(
        addressLine: draft.addressLine,
        postalCode: draft.postalCode,
        city: draft.city,
      );
      lat = geo?.lat;
      lng = geo?.lng;
    }

    final row = await SupabaseService.client
        .from('lm_orders')
        .insert({
          ...draft.toInsertJson(cid),
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
        })
        .select()
        .single();
    return LmOrder.fromJson(row);
  }

  static Future<void> updateStatus(String orderId, String status) async {
    await SupabaseService.client.from('lm_orders').update({'status': status}).eq('id', orderId);
  }

  static Future<int> importFromPdfText(String pdfText, {String source = 'pdf_import'}) async {
    final cid = await _companyId();
    if (cid == null) return 0;

    final stops = RoutePdfTextService.parseCustomers(pdfText);
    if (stops.isEmpty) return 0;

    final routeDate = RoutePdfTextService.parseRouteDate(pdfText) ?? DateTime.now();
    final day = DateTime(routeDate.year, routeDate.month, routeDate.day);
    var count = 0;

    for (final stop in stops) {
      final postal = stop.postalCode;
      final city = _cityFromHint(stop.addressHint, postal);
      final window = _parseWindow(stop.deliveryWindow, day);

      final order = LmOrder(
        id: '',
        companyId: cid,
        source: source,
        customerName: stop.name,
        customerPhone: stop.phoneDisplay,
        addressLine: stop.addressHint ?? '${postal ?? ''} $city'.trim(),
        postalCode: postal,
        city: city,
        timeWindowStart: window?.$1,
        timeWindowEnd: window?.$2,
        weightKg: 35,
        createdAt: DateTime.now(),
      );

      if (await create(order) != null) count++;
    }
    return count;
  }

  static String? _cityFromHint(String? hint, String? postal) {
    if (hint == null) return null;
    final m = RegExp(r'\b\d{4}\s+([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå\s.-]{1,30})').firstMatch(hint);
    return m?.group(1)?.trim();
  }

  static (DateTime, DateTime)? _parseWindow(String? w, DateTime day) {
    if (w == null || !w.contains('–') && !w.contains('-')) return null;
    final parts = w.split(RegExp(r'[–\-]'));
    if (parts.length < 2) return null;
    final start = _hm(parts[0].trim(), day);
    final end = _hm(parts[1].trim(), day);
    if (start == null || end == null) return null;
    return (start, end);
  }

  static DateTime? _hm(String t, DateTime day) {
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static Future<int> geocodePending() async {
    final pending = await fetchPending();
    var n = 0;
    for (final o in pending) {
      if (o.hasCoordinates) continue;
      final geo = await PostalGeocodeService.resolve(
        addressLine: o.addressLine,
        postalCode: o.postalCode,
        city: o.city,
      );
      if (geo == null) continue;
      await SupabaseService.client.from('lm_orders').update({
        'lat': geo.lat,
        'lng': geo.lng,
      }).eq('id', o.id);
      n++;
    }
    return n;
  }
}
