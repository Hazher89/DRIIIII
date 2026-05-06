import 'dart:convert';

import 'package:http/http.dart' as http;

/// Brønnøysundregistrene – åpent API (enhetsregisteret).
/// https://data.brreg.no/enhetsregisteret/api/docs/index.html
class BrregService {
  static const _base = 'https://data.brreg.no/enhetsregisteret/api';

  static Future<List<BrregCompanyHit>> searchByName(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final uri = Uri.parse('$_base/enheter?navn=${Uri.encodeQueryComponent(q)}&size=30');
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception('Brreg søk feilet (${res.statusCode})');
    }
    final map = json.decode(res.body) as Map<String, dynamic>;
    final embed = map['_embedded'];
    if (embed == null) return [];
    final list = embed['enheter'] as List<dynamic>? ?? [];
    return list.map((e) => BrregCompanyHit.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<BrregCompanyDetails?> fetchByOrgNumber(String orgNr) async {
    final clean = orgNr.replaceAll(RegExp(r'\s'), '');
    if (clean.length != 9) return null;
    final uri = Uri.parse('$_base/enheter/$clean');
    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('Brreg oppslag feilet (${res.statusCode})');
    }
    final map = json.decode(res.body) as Map<String, dynamic>;
    return BrregCompanyDetails.fromJson(map);
  }
}

class BrregCompanyHit {
  final String orgNumber;
  final String name;
  final String? city;

  BrregCompanyHit({required this.orgNumber, required this.name, this.city});

  factory BrregCompanyHit.fromJson(Map<String, dynamic> json) {
    return BrregCompanyHit(
      orgNumber: json['organisasjonsnummer']?.toString() ?? '',
      name: json['navn']?.toString() ?? '',
      city: json['forretningsadresse'] != null
          ? (json['forretningsadresse'] as Map)['poststed']?.toString()
          : null,
    );
  }
}

class BrregCompanyDetails {
  final String orgNumber;
  final String name;
  final String? tradeName;
  final String? legalForm;
  final String? street;
  final String? postalCode;
  final String? city;
  final String? country;
  final String? phone;
  final String? email;
  final String? dailyLeaderName;
  final Map<String, dynamic> raw;

  BrregCompanyDetails({
    required this.orgNumber,
    required this.name,
    this.tradeName,
    this.legalForm,
    this.street,
    this.postalCode,
    this.city,
    this.country,
    this.phone,
    this.email,
    this.dailyLeaderName,
    required this.raw,
  });

  factory BrregCompanyDetails.fromJson(Map<String, dynamic> json) {
    final addr = json['forretningsadresse'] as Map<String, dynamic>?;
    final dagl = json['dagligLeder'] as Map<String, dynamic>?;
    String? leader;
    if (dagl != null) {
      final fn = dagl['fornavn']?.toString() ?? '';
      final en = dagl['etternavn']?.toString() ?? '';
      leader = ('$fn $en').trim();
      if (leader.isEmpty) leader = null;
    }

    return BrregCompanyDetails(
      orgNumber: json['organisasjonsnummer']?.toString() ?? '',
      name: json['navn']?.toString() ?? '',
      tradeName: null,
      legalForm: json['organisasjonsform'] is Map
          ? (json['organisasjonsform'] as Map)['beskrivelse']?.toString()
          : null,
      street: addr != null
          ? _formatAddress(addr)
          : null,
      postalCode: addr?['postnummer']?.toString(),
      city: addr?['poststed']?.toString(),
      country: addr?['land']?.toString(),
      phone: json['telefon']?.toString(),
      email: json['epost']?.toString() ?? json['epostadresse']?.toString(),
      dailyLeaderName: leader,
      raw: json,
    );
  }

  static String _formatAddress(Map<String, dynamic> addr) {
    final parts = addr['adresse'];
    if (parts is List) {
      return parts.map((e) => e.toString()).where((e) => e.isNotEmpty).join(', ');
    }
    return addr['adresse']?.toString() ?? '';
  }
}
