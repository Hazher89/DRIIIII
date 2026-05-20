/// Norsk mobilnormalisering — matcher `public.normalize_phone_no` i Supabase.
String? normalizePhoneNo(String? phone) {
  if (phone == null || phone.trim().isEmpty) return null;
  final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.length == 8 && RegExp(r'^[49]').hasMatch(d)) return '47$d';
  if (d.length == 10 && RegExp(r'^47[49]').hasMatch(d)) return d;
  if (d.length == 11 && d.startsWith('047')) return d.substring(1);
  if (d.length >= 10 && d.startsWith('47')) return d.substring(0, d.length.clamp(0, 11));
  return null;
}

/// Visning: 8 siffer uten landskode.
String displayPhoneNo(String normalizedOrRaw) {
  final n = normalizePhoneNo(normalizedOrRaw);
  if (n == null) return normalizedOrRaw;
  if (n.length == 10 && n.startsWith('47')) return n.substring(2);
  return n;
}
