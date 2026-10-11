import 'dart:math';

import '../services/partner/mavi_unit_codes.dart';

/// Genererer innloggingsdata for MAVI-sjåfør og bil-eier.
class PortalCredentials {
  PortalCredentials._();

  static final _rng = Random.secure();

  static const _portalDomain = 'portal.driftpro.no';

  /// Samme startpassord for alle partnerportaler. De bytter selv under Mer.
  static const defaultPassword = '000000';

  static const _legalSuffixes = {
    'as', 'asa', 'da', 'ans', 'enk', 'nuf', 'sa', 'ba', 'ab', 'co', 'ltd',
  };

  /// Lett brukernavn av bedriftsnavnet, f.eks. «ALT SAMMEN 24 AS» → `altsammen24`.
  static String companyUsername(String partnerName) {
    final words = partnerName.trim().split(RegExp(r'\s+'));
    final kept = <String>[];
    for (final word in words) {
      final slug = _slug(word);
      if (slug.isEmpty || _legalSuffixes.contains(slug)) continue;
      kept.add(slug);
    }
    var out = kept.join();
    if (out.length < 3) out = _slug(partnerName);
    if (out.length < 3) out = 'partner';
    if (out.length > 18) out = out.substring(0, 18);
    return out;
  }

  /// Sjåfør: kort og knyttet til MAVI-nummer — f.eks. `m71` for NO_O_M0071.
  static String driverUsername(String unitCode) {
    final n = MaviUnitCodes.normalize(unitCode);
    final m = RegExp(r'NO_O_M0*(\d{1,5})').firstMatch(n);
    if (m != null) {
      final num = int.tryParse(m.group(1)!);
      if (num != null) return 'm$num';
    }
    final compact = n.replaceAll(RegExp(r'[^A-Z0-9]'), '').toLowerCase();
    if (compact.length >= 2) {
      return compact.length > 12 ? compact.substring(0, 12) : compact;
    }
    return 'sj${10 + _rng.nextInt(89)}';
  }

  /// Bil-eier: bedriftsnavnet som brukernavn, f.eks. `altsammen24`.
  static String ownerUsername({
    required String partnerName,
    String? orgNumber,
    String? partnerId,
    String? phone,
  }) {
    return companyUsername(partnerName);
  }

  @Deprecated('Use ownerUsername(partnerName:, orgNumber:, partnerId:)')
  static String ownerUsernameFromId(String partnerId) {
    return 'eier${_idTail(partnerId, 4)}';
  }

  /// Kort teknisk Auth-e-post (brukernavn er det brukeren logger inn med).
  static String loginEmail({
    required String partnerId,
    required bool isOwner,
    String? partnerVehicleId,
    String? ownerPhone,
    bool isStaff = false,
    String? staffId,
  }) {
    final scopeId = isOwner
        ? partnerId
        : (isStaff ? (staffId ?? partnerId) : (partnerVehicleId ?? partnerId));
    final hex = scopeId.replaceAll('-', '');
    final short = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
    final prefix = isOwner ? 'o' : (isStaff ? 's' : 'd');
    if (isOwner && ownerPhone != null) {
      final phoneDigits = ownerPhone.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.length >= 4) {
        final phoneTail = phoneDigits.substring(phoneDigits.length - 4);
        return '$prefix.$short.$phoneTail@$_portalDomain';
      }
    }
    return '$prefix.$short@$_portalDomain';
  }

  /// Unikt brukernavn for partner-ansatt — knyttet til firma + person.
  static String staffUsername({
    required String partnerName,
    required String fullName,
    required String phone,
    required String staffId,
  }) {
    final firm = companyUsername(partnerName);
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    final person = (_slug(first).isNotEmpty ? _slug(first) : 'ans');
    final personShort = person.length > 8 ? person.substring(0, 8) : person;
    final combined = '$firm$personShort';
    return combined.length > 22 ? combined.substring(0, 22) : combined;
  }

  static String displayLoginHint({
    required String username,
    required String password,
    required bool isOwner,
    bool isStaff = false,
  }) {
    if (isOwner) {
      return 'Brukernavn: $username\nPassord: $password\n'
          '(Logg inn med brukernavn + passord på driftpro.no)';
    }
    if (isStaff) {
      return 'Brukernavn: $username\nPassord: $password\n'
          '(Kun partnerportalen — stempling for din bedrift)';
    }
    return 'Brukernavn: $username\nPassord: $password\n'
        '(Kun dine tildelte ruter i portalen)';
  }

  /// Klar tekst for å sende til ansatt (SMS/mail).
  static String shareCredentialsMessage({
    required String fullName,
    required String username,
    required String password,
    required String partnerName,
  }) {
    return 'Hei $fullName!\n\n'
        'Innlogging til DriftPro for $partnerName:\n'
        'Brukernavn: $username\n'
        'Passord: $password\n\n'
        'Åpne DriftPro → velg «Partnere» (ikke «Ansatte»).\n'
        'Logg inn med brukernavn og passord over.\n'
        'Kontoen er kun for deg hos $partnerName — partnerportalen (stempling).';
  }

  static String _slug(String text) {
    var s = text.toLowerCase().trim();
    s = s
        .replaceAll('æ', 'ae')
        .replaceAll('ø', 'o')
        .replaceAll('å', 'a')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return s;
  }

  static String _idTail(String? id, int len) {
    if (id == null || id.isEmpty) {
      return (10 + _rng.nextInt(8999)).toString();
    }
    final hex = id.replaceAll('-', '');
    return hex.length >= len ? hex.substring(0, len) : hex.padRight(len, '0');
  }

  /// Standardpassord for nye partnerportaler. Superadmin kan overstyre.
  static String generatePassword({int length = 6}) => defaultPassword;
}
