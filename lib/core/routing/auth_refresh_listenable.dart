import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Varsler [GoRouter] når innlogging endres (redirect login ↔ app).
class AuthRefreshListenable extends ChangeNotifier {
  AuthRefreshListenable() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}
