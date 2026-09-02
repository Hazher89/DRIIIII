import '../core/constants/company_principals.dart';

/// Mottaker for anonym anmeldelse / anonymt avvik — kun Tommy, Nico, Hazher.
enum WhistlePrincipal {
  tommy,
  nico,
  hazher;

  String get dbValue => name;

  String get label => switch (this) {
        WhistlePrincipal.tommy => 'Tommy Larsen',
        WhistlePrincipal.nico => 'Nicola Vino',
        WhistlePrincipal.hazher => 'Hazher Abdullah',
      };

  String get title => switch (this) {
        WhistlePrincipal.tommy => CompanyPrincipal.tommy.title,
        WhistlePrincipal.nico => CompanyPrincipal.nico.title,
        WhistlePrincipal.hazher => CompanyPrincipal.hazher.title,
      };

  CompanyPrincipal get companyPrincipal => switch (this) {
        WhistlePrincipal.tommy => CompanyPrincipal.tommy,
        WhistlePrincipal.nico => CompanyPrincipal.nico,
        WhistlePrincipal.hazher => CompanyPrincipal.hazher,
      };

  static WhistlePrincipal? fromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'tommy':
        return WhistlePrincipal.tommy;
      case 'nico':
        return WhistlePrincipal.nico;
      case 'hazher':
        return WhistlePrincipal.hazher;
      default:
        return null;
    }
  }

  static List<WhistlePrincipal> listFromDb(dynamic raw) {
    if (raw is! List) return const [];
    final out = <WhistlePrincipal>[];
    for (final item in raw) {
      final p = fromDb(item?.toString());
      if (p != null && !out.contains(p)) out.add(p);
    }
    return out;
  }
}

class WhistleblowingReport {
  final String id;
  final String companyId;
  final String title;
  final String description;
  final List<String> imageUrls;
  /// Hvem som skal varsles — minst én av Tommy / Nico / Hazher.
  final List<WhistlePrincipal> recipientPrincipals;
  final DateTime? createdAt;

  const WhistleblowingReport({
    required this.id,
    required this.companyId,
    required this.title,
    required this.description,
    this.imageUrls = const [],
    this.recipientPrincipals = const [
      WhistlePrincipal.tommy,
      WhistlePrincipal.nico,
      WhistlePrincipal.hazher,
    ],
    this.createdAt,
  });

  factory WhistleblowingReport.fromJson(Map<String, dynamic> json) {
    var principals =
        WhistlePrincipal.listFromDb(json['recipient_principals']);
    // Bakoverkompatibilitet med gammel recipient_scope
    if (principals.isEmpty) {
      final scope = json['recipient_scope'] as String?;
      if (scope == 'leader') {
        // Gammel «leder» → send til hele ledelsen (ikke avd.leder)
        principals = WhistlePrincipal.values.toList();
      } else {
        principals = WhistlePrincipal.values.toList();
      }
    }
    return WhistleblowingReport(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      recipientPrincipals: principals,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'title': title,
        'description': description,
        'image_urls': imageUrls,
        'recipient_principals':
            recipientPrincipals.map((p) => p.dbValue).toList(),
        'recipient_scope': 'leadership',
      };
}
