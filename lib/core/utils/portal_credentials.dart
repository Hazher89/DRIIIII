import 'dart:math';

/// Genererer innloggingsdata for MAVI-sjåfør og bil-eier.
class PortalCredentials {
  PortalCredentials._();

  static final _rng = Random.secure();

  static String driverUsername(String unitCode) {
    final u = unitCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (u.isEmpty) return 'sjafør${1000 + _rng.nextInt(8999)}';
    return 'mavi_${u.toLowerCase()}';
  }

  static String ownerUsername(String partnerId) {
    final short = partnerId.replaceAll('-', '').substring(0, 6);
    return 'eier_$short';
  }

  static String generatePassword({int length = 10}) {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return List.generate(length, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  static String loginEmail({
    required String username,
    required String companyId,
    required bool isOwner,
  }) {
    final user = username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '');
    final cid = companyId.replaceAll('-', '').substring(0, 8);
    final prefix = isOwner ? 'eier' : 'mavi';
    return '$user@$prefix.$cid.portal';
  }
}
