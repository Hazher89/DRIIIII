/// Norsk mobilnormalisering — matcher `public.normalize_phone_no` i Supabase.
String? normalizePhoneNo(String? phone) {
  if (phone == null || phone.trim().isEmpty) return null;
  var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;

  // Fjern vanlig landskode-prefix.
  if (d.startsWith('0047') && d.length >= 12) {
    d = d.substring(4);
  } else if (d.startsWith('47') && d.length >= 10) {
    d = d.substring(2);
  }

  // 8 siffer: 4xxx / 9xxx
  if (d.length == 8 && RegExp(r'^[49]').hasMatch(d)) return '47$d';

  // Vanlig tastefeil: 9–10 siffer som starter med 4/9 — bruk første 8 om gyldig.
  if ((d.length == 9 || d.length == 10) && RegExp(r'^[49]').hasMatch(d)) {
    final eight = d.substring(0, 8);
    if (RegExp(r'^[49]\d{7}$').hasMatch(eight)) return '47$eight';
  }

  if (d.length == 10 && RegExp(r'^47[49]').hasMatch(d)) return d;
  if (d.length == 11 && d.startsWith('047')) return d.substring(1);
  return null;
}

/// True når nummeret er gyldig norsk mobil (etter normalisering).
bool isValidNorwegianMobile(String? phone) => normalizePhoneNo(phone) != null;

/// Visning: 8 siffer uten landskode.
String displayPhoneNo(String normalizedOrRaw) {
  final n = normalizePhoneNo(normalizedOrRaw);
  if (n == null) return normalizedOrRaw;
  if (n.length == 10 && n.startsWith('47')) return n.substring(2);
  return n;
}
