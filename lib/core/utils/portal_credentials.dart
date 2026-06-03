import 'dart:math';

import '../services/partner/mavi_unit_codes.dart';

/// Genererer innloggingsdata for MAVI-sjåfør og bil-eier.
class PortalCredentials {
  PortalCredentials._();

  static final _rng = Random.secure();

  static const _portalDomain = 'portal.driftpro.no';

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

  /// Bil-eier: kort brukernavn — f.eks. `eierhaz8382` (firma-init + org.siste 4).
  /// Med [phone] brukes siste 4 siffer for unikt brukernavn per bil-eier.
  static String ownerUsername({
    required String partnerName,
    String? orgNumber,
    String? partnerId,
    String? phone,
  }) {
    final initials = _partnerInitials(partnerName, maxLen: 3);
    final phoneDigits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length >= 4) {
      return 'eier$initials${phoneDigits.substring(phoneDigits.length - 4)}';
    }
    final org = (orgNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final tail = org.length >= 4
        ? org.substring(org.length - 4)
        : _idTail(partnerId, 4);
    return 'eier$initials$tail';
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
  }) {
    final scopeId = isOwner
        ? partnerId
        : (partnerVehicleId ?? partnerId);
    final hex = scopeId.replaceAll('-', '');
    final short = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
    final prefix = isOwner ? 'o' : 'd';
    if (isOwner && ownerPhone != null) {
      final phoneDigits = ownerPhone.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.length >= 4) {
        final phoneTail = phoneDigits.substring(phoneDigits.length - 4);
        return '$prefix.$short.$phoneTail@$_portalDomain';
      }
    }
    return '$prefix.$short@$_portalDomain';
  }

  static String displayLoginHint({
    required String username,
    required String password,
    required bool isOwner,
  }) {
    return isOwner
        ? 'Brukernavn: $username\nPassord: $password\n(Logg inn med brukernavn + passord på driftpro.no)'
        : 'Brukernavn: $username\nPassord: $password\n(Kun dine tildelte ruter i portalen)';
  }

  static String _partnerInitials(String partnerName, {required int maxLen}) {
    final words = partnerName.trim().split(RegExp(r'\s+'));
    final buf = StringBuffer();
    for (final w in words) {
      if (w.isEmpty) continue;
      final c = _firstAsciiLetter(w);
      if (c != null) buf.write(c);
      if (buf.length >= maxLen) break;
    }
    var out = buf.toString().toLowerCase();
    if (out.length < 2) {
      final slug = _slug(partnerName);
      out = slug.length >= 2 ? slug.substring(0, 2) : 'bp';
    }
    return out.length > maxLen ? out.substring(0, maxLen) : out;
  }

  static String? _firstAsciiLetter(String word) {
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune).toLowerCase();
      if (ch == 'æ') return 'a';
      if (ch == 'ø') return 'o';
      if (ch == 'å') return 'a';
      if (RegExp(r'[a-z]').hasMatch(ch)) return ch;
    }
    return null;
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

  /// Lett å lese på SMS — ord + tall, f.eks. `Nord42`.
  static String generatePassword({int length = 10}) {
    const words = [
      'Nord', 'Elg', 'Bjork', 'Fjord', 'Moze', 'Sno', 'Hav', 'Laks',
      'Elv', 'Tind', 'Ro', 'Li',
    ];
    final word = words[_rng.nextInt(words.length)];
    final n = 10 + _rng.nextInt(89);
    final pwd = '$word$n';
    if (pwd.length >= length) return pwd;
    const chars = '23456789';
    return pwd + chars[_rng.nextInt(chars.length)];
  }
}
