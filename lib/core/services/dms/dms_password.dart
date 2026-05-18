import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Enkel mappepassord-hashing (lagres ikke i klartekst).
class DmsPassword {
  DmsPassword._();

  static String hash(String password) {
    final bytes = utf8.encode(password.trim());
    return sha256.convert(bytes).toString();
  }

  static bool verify(String password, String? storedHash) {
    if (storedHash == null || storedHash.isEmpty) return true;
    if (password.trim().isEmpty) return false;
    return hash(password) == storedHash;
  }
}
