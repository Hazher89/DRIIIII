import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'work_steps_health_bridge.dart';
import 'work_steps_privacy.dart';
import 'work_steps_service.dart';

class WorkStepsSyncResult {
  const WorkStepsSyncResult({
    required this.ok,
    required this.message,
    this.steps,
    this.atWorkplace = false,
    this.openSettingsHint = false,
  });

  final bool ok;
  final String message;
  final int? steps;
  final bool atWorkplace;
  final bool openSettingsHint;
}

/// Synk skritt kun ved aktivt samtykke + telefon innenfor MAVI arbeidssted.
///
/// Ingen kontinuerlig GPS-sporing: én «when in use»-sjekk ved synk.
class WorkStepsSync {
  WorkStepsSync._();

  static Future<WorkStepsSyncResult> syncNow() async {
    final consent = await WorkStepsService.fetchMyConsent();
    if (consent == null || !consent.enabled) {
      return const WorkStepsSyncResult(
        ok: false,
        message: 'Skritt på jobb er slått av. Slå på for å dele skritt.',
      );
    }

    final settings = await WorkStepsService.fetchSettings();
    if (settings == null || !settings.enabled) {
      return const WorkStepsSyncResult(
        ok: false,
        message: 'Funksjonen er ikke aktivert for bedriften ennå.',
      );
    }
    if (!settings.hasWorkplace) {
      return const WorkStepsSyncResult(
        ok: false,
        message:
            'Arbeidssted er ikke satt i hub. Kontakt leder før skritt kan synkes.',
      );
    }

    final location = await _ensureLocationReady();
    if (location != null) return location;

    final atWork = await _isAtWorkplace(settings);
    if (!atWork) {
      return const WorkStepsSyncResult(
        ok: false,
        message: kWorkStepsNotAtWorkMessage,
        atWorkplace: false,
      );
    }

    if (!await WorkStepsHealthBridge.isSupported()) {
      return const WorkStepsSyncResult(
        ok: false,
        message:
            'Skritt synkes i DriftPro-appen på iPhone eller Android — ikke i nettleser.',
        atWorkplace: true,
      );
    }

    final steps = await WorkStepsHealthBridge.stepsToday();
    if (steps == null) {
      return const WorkStepsSyncResult(
        ok: false,
        message:
            'Kunne ikke lese skritt. Sjekk tillatelser i Apple Helse / Health Connect '
            'og at DriftPro har tilgang til Skritt.',
        atWorkplace: true,
        openSettingsHint: true,
      );
    }

    await WorkStepsService.upsertTodaySteps(
      steps: steps,
      atWorkplace: true,
    );

    return WorkStepsSyncResult(
      ok: true,
      message:
          'Synket $steps skritt på jobb i dag (${settings.workplaceName}).',
      steps: steps,
      atWorkplace: true,
    );
  }

  /// Null = OK. Ellers feilmelding for bruker.
  static Future<WorkStepsSyncResult?> _ensureLocationReady() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      return const WorkStepsSyncResult(
        ok: false,
        message:
            'Posisjon er slått av på telefonen. Slå på posisjon og prøv igjen.',
        openSettingsHint: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const WorkStepsSyncResult(
        ok: false,
        message:
            'Posisjonstilgang trengs for å bekrefte at du er på arbeidsstedet.',
        openSettingsHint: true,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const WorkStepsSyncResult(
        ok: false,
        message:
            'Posisjon er blokkert for DriftPro. Åpne Innstillinger og tillat posisjon «Når appen er i bruk».',
        openSettingsHint: true,
      );
    }

    // Android: også permission_handler (noen OEM-er).
    final ph = await Permission.locationWhenInUse.status;
    if (ph.isDenied) {
      final req = await Permission.locationWhenInUse.request();
      if (!req.isGranted) {
        return const WorkStepsSyncResult(
          ok: false,
          message: 'Posisjonstilgang mangler. Tillat posisjon for DriftPro.',
          openSettingsHint: true,
        );
      }
    }

    return null;
  }

  /// Én lokasjonssjekk (when-in-use). Ingen bakgrunnssporing.
  static Future<bool> _isAtWorkplace(WorkStepsSettings settings) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final meters = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        settings.workplaceLat!,
        settings.workplaceLng!,
      );
      return meters <= settings.radiusMeters;
    } catch (_) {
      return false;
    }
  }
}
