import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import 'user_access.dart';

/// Naviger til en hovedfane via tilgangsnøkkel (ikke hardkodet indeks).
typedef NavigateByAccess = void Function(String accessKey);

/// MaterialRoute som blokkerer innhold uten tilgang (direkte lenker / dyp navigasjon).
Route<T> guardedMaterialRoute<T>({
  required UserProfile? profile,
  required String accessKey,
  required Widget child,
  String deniedMessage = 'Du har ikke tilgang til denne siden.',
}) {
  return MaterialPageRoute<T>(
    builder: (_) => PermissionGuard(
      profile: profile,
      accessKey: accessKey,
      deniedMessage: deniedMessage,
      child: child,
    ),
  );
}

/// Viser [child] bare når brukeren har tilgang til [accessKey].
class PermissionGate extends StatelessWidget {
  final UserProfile? profile;
  final String accessKey;
  final Widget child;
  final Widget? fallback;

  const PermissionGate({
    super.key,
    required this.profile,
    required this.accessKey,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (profile != null && profile!.access.can(accessKey)) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}

/// Skjerm som blokkeres hvis tilgang mangler (ekstra sikkerhet ved direkte navigasjon).
class PermissionGuard extends StatelessWidget {
  final UserProfile? profile;
  final String accessKey;
  final Widget child;
  final String deniedMessage;

  const PermissionGuard({
    super.key,
    required this.profile,
    required this.accessKey,
    required this.child,
    this.deniedMessage = 'Du har ikke tilgang til denne siden.',
  });

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (profile!.access.can(accessKey)) {
      return child;
    }
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text(
                deniedMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
