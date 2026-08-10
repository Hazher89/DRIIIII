import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import 'access_actions.dart';
import 'user_access.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Naviger til en hovedfane via tilgangsnøkkel (ikke hardkodet indeks).
typedef NavigateByAccess = void Function(String accessKey);

/// MaterialRoute som blokkerer innhold uten tilgang (direkte lenker / dyp navigasjon).
Route<T> guardedMaterialRoute<T>({
  required UserProfile? profile,
  required String accessKey,
  required Widget child,
  String deniedMessage = 'Du har ikke tilgang til denne siden.',
  String? areaId,
  AccessAction action = AccessAction.view,
}) {
  return MaterialPageRoute<T>(
    builder: (_) => PermissionGuard(
      profile: profile,
      accessKey: accessKey,
      areaId: areaId,
      action: action,
      deniedMessage: deniedMessage,
      child: child,
    ),
  );
}

/// Viser [child] bare når brukeren har tilgang.
class PermissionGate extends StatelessWidget {
  final UserProfile? profile;
  final String? accessKey;
  final String? areaId;
  final AccessAction action;
  final Widget child;
  final Widget? fallback;

  const PermissionGate({
    super.key,
    required this.profile,
    required this.child,
    this.accessKey,
    this.areaId,
    this.action = AccessAction.view,
    this.fallback,
  });

  bool _allowed() {
    if (profile == null) return false;
    final access = profile!.access;
    if (areaId != null) return access.canArea(areaId!, action);
    if (accessKey != null) return access.can(accessKey!);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed()) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

/// Skjerm som blokkeres hvis tilgang mangler.
class PermissionGuard extends StatelessWidget {
  final UserProfile? profile;
  final String? accessKey;
  final String? areaId;
  final AccessAction action;
  final Widget child;
  final String deniedMessage;

  const PermissionGuard({
    super.key,
    required this.profile,
    required this.child,
    this.accessKey,
    this.areaId,
    this.action = AccessAction.view,
    this.deniedMessage = 'Du har ikke tilgang til denne siden.',
  });

  bool _allowed() {
    if (profile == null) return false;
    final access = profile!.access;
    if (areaId != null) return access.canArea(areaId!, action);
    if (accessKey != null) return access.can(accessKey!);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const Scaffold(
        body: DriftProLoadingCenter(),
      );
    }
    if (_allowed()) {
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
