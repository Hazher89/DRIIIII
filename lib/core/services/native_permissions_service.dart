import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/driftpro_client.dart';
import '../theme/app_theme.dart';
import 'notification/push_notification_service.dart';

/// Tillatelser DriftPro ber om (med norsk forklaring før systemdialogen — Apple HIG).
enum AppPermissionKind {
  notifications,
  camera,
  photos,
  location,
  microphone,
}

extension AppPermissionKindX on AppPermissionKind {
  String get title => switch (this) {
        AppPermissionKind.notifications => 'Varsler',
        AppPermissionKind.camera => 'Kamera',
        AppPermissionKind.photos => 'Bilder',
        AppPermissionKind.location => 'Posisjon',
        AppPermissionKind.microphone => 'Mikrofon',
      };

  String get rationale => switch (this) {
        AppPermissionKind.notifications =>
          'DriftPro sender varsler om nye ruter, godkjenninger, fravær, avvik og viktige '
          'oppdateringer fra jobben. Uten varsler kan du gå glipp av oppgaver.',
        AppPermissionKind.camera =>
          'Kamera brukes til avviksbilder, bilutleie-dokumentasjon, strekkodeskanning '
          'og GM & STORO-etiketter — kun når du selv tar bilde i appen.',
        AppPermissionKind.photos =>
          'Tilgang til bilder brukes når du velger vedlegg til avvik, HMS, personalmappe '
          'eller andre dokumenter. Vi laster ikke opp bilder uten at du velger dem.',
        AppPermissionKind.location =>
          'Posisjon brukes når du melder avvik med sted, følger levering/sjåføroppgaver '
          'eller dokumenterer GPS i jobbsammenheng — mens appen er i bruk.',
        AppPermissionKind.microphone =>
          'Mikrofon brukes kun hvis du tar video med lyd som dokumentasjon. '
          'Vanlige stillbilder trenger ikke mikrofon.',
      };

  String get deniedMessage => switch (this) {
        AppPermissionKind.notifications =>
          'Varsler er slått av. Du kan aktivere dem under Innstillinger → DriftPro.',
        AppPermissionKind.camera =>
          'Kameratilgang mangler. Åpne Innstillinger for å tillate kamera.',
        AppPermissionKind.photos =>
          'Bildetilgang mangler. Åpne Innstillinger for å tillate bilder.',
        AppPermissionKind.location =>
          'Posisjonstilgang mangler. Åpne Innstillinger for å tillate posisjon.',
        AppPermissionKind.microphone =>
          'Mikrofontilgang mangler. Åpne Innstillinger for å tillate mikrofon.',
      };

  IconData get icon => switch (this) {
        AppPermissionKind.notifications => Icons.notifications_active_outlined,
        AppPermissionKind.camera => Icons.photo_camera_outlined,
        AppPermissionKind.photos => Icons.photo_library_outlined,
        AppPermissionKind.location => Icons.location_on_outlined,
        AppPermissionKind.microphone => Icons.mic_none_outlined,
      };

  Permission get permission => switch (this) {
        AppPermissionKind.notifications => Permission.notification,
        AppPermissionKind.camera => Permission.camera,
        AppPermissionKind.photos => Permission.photos,
        AppPermissionKind.location => Permission.locationWhenInUse,
        AppPermissionKind.microphone => Permission.microphone,
      };
}

/// Native tillatelser (iOS/Android) med forklaring før systempopup.
abstract final class NativePermissionsService {
  static bool get _native => DriftProClient.isMobile;

  static const _hiveBox = 'driftpro_permissions';
  static const _onboardingKey = 'onboarding_v2_done';

  static Future<bool> ensureNotifications({
    BuildContext? context,
    bool showRationale = true,
  }) =>
      ensure(
        AppPermissionKind.notifications,
        context: context,
        showRationale: showRationale,
      );

  static Future<bool> ensureCamera({
    BuildContext? context,
    bool showRationale = true,
  }) =>
      ensure(AppPermissionKind.camera, context: context, showRationale: showRationale);

  static Future<bool> ensurePhotos({
    BuildContext? context,
    bool showRationale = true,
  }) =>
      ensure(AppPermissionKind.photos, context: context, showRationale: showRationale);

  static Future<bool> ensureLocation({
    BuildContext? context,
    bool showRationale = true,
  }) =>
      ensure(AppPermissionKind.location, context: context, showRationale: showRationale);

  static Future<bool> ensureMicrophone({
    BuildContext? context,
    bool showRationale = true,
  }) =>
      ensure(AppPermissionKind.microphone, context: context, showRationale: showRationale);

  /// Ber om tillatelse. Viser norsk forklaring før iOS/Android-dialogen når [context] er satt.
  static Future<bool> ensure(
    AppPermissionKind kind, {
    BuildContext? context,
    bool showRationale = true,
  }) async {
    if (!_native) return true;

    if (kind == AppPermissionKind.location) {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (context != null && context.mounted) {
          await _showSettingsHint(
            context,
            title: 'Posisjon er slått av',
            message:
                'Skru på posisjonstjenester på enheten for at DriftPro skal kunne '
                'registrere sted på avvik og leveringsoppgaver.',
          );
        }
        return false;
      }
    }

    final permission = kind.permission;
    var status = await permission.status;
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (context != null && context.mounted) {
        await _showSettingsHint(
          context,
          title: '${kind.title} er blokkert',
          message: kind.deniedMessage,
        );
      }
      return false;
    }

    if (showRationale && context != null && context.mounted) {
      final proceed = await _showRationaleDialog(context, kind);
      if (!proceed) return false;
      if (!context.mounted) return false;
    }

    status = await permission.request();
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  /// Etter innlogging: forklar + be om tillatelser (én gang per enhet).
  static Future<void> bootstrapAfterLogin([BuildContext? context]) async {
    if (!_native) return;

    if (context != null && context.mounted) {
      await showPermissionOnboardingIfNeeded(context);
    } else {
      await ensureNotifications(showRationale: false);
    }

    await PushNotificationService.bootstrapAfterLogin();
  }

  static Future<void> showPermissionOnboardingIfNeeded(BuildContext context) async {
    if (!_native || !context.mounted) return;

    try {
      await Hive.initFlutter();
      final box = await Hive.openBox(_hiveBox);
      if (box.get(_onboardingKey) == true) {
        // Alltid sikre varsler etter login (kan ha blitt avslått tidligere).
        if (context.mounted) {
          await ensureNotifications(context: context, showRationale: false);
        }
        return;
      }
    } catch (_) {}

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PermissionOnboardingSheet(),
    );

    try {
      final box = await Hive.openBox(_hiveBox);
      await box.put(_onboardingKey, true);
    } catch (_) {}
  }

  /// Vis snackbar + lenke til Innstillinger ved permanent avslag.
  static Future<bool> ensureOrPrompt(
    BuildContext context, {
    required Future<bool> Function() ensure,
    required String deniedMessage,
  }) async {
    final ok = await ensure();
    if (ok || !context.mounted) return ok;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deniedMessage),
        action: SnackBarAction(
          label: 'Innstillinger',
          onPressed: openAppSettings,
        ),
        duration: const Duration(seconds: 6),
      ),
    );
    return false;
  }

  static Future<bool> _showRationaleDialog(
    BuildContext context,
    AppPermissionKind kind,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(kind.icon, color: DriftProTheme.primaryGreen, size: 36),
        title: Text('Tillat ${kind.title.toLowerCase()}'),
        content: Text(kind.rationale, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ikke nå'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            child: const Text('Fortsett'),
          ),
        ],
      ),
    );
    return result == true;
  }

  static Future<void> _showSettingsHint(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Åpne Innstillinger'),
          ),
        ],
      ),
    );
  }
}

class _PermissionOnboardingSheet extends StatefulWidget {
  const _PermissionOnboardingSheet();

  @override
  State<_PermissionOnboardingSheet> createState() => _PermissionOnboardingSheetState();
}

class _PermissionOnboardingSheetState extends State<_PermissionOnboardingSheet> {
  static const _order = <AppPermissionKind>[
    AppPermissionKind.notifications,
    AppPermissionKind.camera,
    AppPermissionKind.photos,
    AppPermissionKind.location,
    AppPermissionKind.microphone,
  ];

  final Map<AppPermissionKind, bool?> _status = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    final next = <AppPermissionKind, bool?>{};
    for (final kind in _order) {
      final s = await kind.permission.status;
      next[kind] = s.isGranted || s.isLimited || s.isProvisional;
    }
    if (mounted) setState(() => _status.addAll(next));
  }

  Future<void> _request(AppPermissionKind kind) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await NativePermissionsService.ensure(
        kind,
        context: context,
        showRationale: true,
      );
      if (mounted) setState(() => _status[kind] = ok);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestAllRemaining() async {
    for (final kind in _order) {
      if (_status[kind] == true) continue;
      if (!mounted) return;
      await _request(kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tillatelser for DriftPro',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Apple krever at vi forklarer hvorfor vi ber om tilgang. '
            'Du kan godta nå eller vente til funksjonen brukes.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.52,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _order.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final kind = _order[i];
                final granted = _status[kind] == true;
                return Material(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          kind.icon,
                          color: granted ? DriftProTheme.success : DriftProTheme.primaryGreen,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kind.title,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                kind.rationale,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (granted)
                          const Icon(Icons.check_circle, color: DriftProTheme.success)
                        else
                          TextButton(
                            onPressed: _busy ? null : () => _request(kind),
                            child: const Text('Tillat'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _requestAllRemaining,
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(_busy ? 'Venter…' : 'Tillat alle som mangler'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Ferdig'),
          ),
        ],
      ),
    );
  }
}
