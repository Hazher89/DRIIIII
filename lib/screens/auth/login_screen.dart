import 'package:flutter/material.dart';

import 'auth_gate_screen.dart';

/// Eldre innloggingsskjerm — videresender til [AuthGateScreen]
/// (ansattnummer / partner, uten Google/Apple).
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const AuthGateScreen();
}
