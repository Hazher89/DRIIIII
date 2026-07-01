import '../../models/user_profile.dart';
import 'access_keys.dart';

/// Forhåndsdefinerte tilgangspakker ved godkjenning.
class AccessPresets {
  AccessPresets._();

  static Map<String, dynamic> employee() => {
        ...AccessKeys.allOff(),
        AccessKeys.dashboard: true,
        AccessKeys.more: true,
        AccessKeys.fravaer: true,
        AccessKeys.avvik: true,
        AccessKeys.whistleblowing: true,
        AccessKeys.profil: true,
        AccessKeys.stempling: true,
      };

  static Map<String, dynamic> departmentLeader() => {
        ...employee(),
        AccessKeys.ansatte: true,
        AccessKeys.ansatteRediger: true,
        AccessKeys.avdelinger: true,
        AccessKeys.fravaerGodkjenn: true,
        AccessKeys.fravaerRegistrerAndre: true,
        AccessKeys.avvikGodkjenn: true,
        AccessKeys.avvikKoordinere: true,
        AccessKeys.surveys: true,
        AccessKeys.hms: true,
        AccessKeys.hmsRisikovurdering: true,
        AccessKeys.hmsSja: true,
        AccessKeys.hmsSikkerhetsrunde: true,
        AccessKeys.hmsUtstyr: true,
        AccessKeys.hmsUtstyrAdmin: true,
        AccessKeys.hmsUtstyrService: true,
        AccessKeys.hmsUtstyrServicehefte: true,
        AccessKeys.hmsKompetanse: true,
        AccessKeys.hmsDokumenter: true,
        AccessKeys.surveyResultater: true,
        AccessKeys.samarbeidspartnere: true,
        AccessKeys.partners: true,
        AccessKeys.partnersAdmin: true,
        AccessKeys.fleetRuter: true,
        AccessKeys.partnersCreate: true,
        AccessKeys.partnersDelete: true,
        AccessKeys.partnersEdit: true,
        AccessKeys.partnersVehicleRental: true,
        AccessKeys.partnersVehicleRentalApprove: true,
        for (final k in AccessKeys.partnerDetailTabKeys) k: true,
        AccessKeys.ferieAdmin: true,
        AccessKeys.stempling: true,
        AccessKeys.stemplingAdmin: true,
        AccessKeys.stemplingInnstillinger: true,
      };

  static Map<String, dynamic> companyAdmin() => {
        ...AccessKeys.allOn(),
        AccessKeys.varsler: false,
        AccessKeys.brukergodkjenning: false,
        AccessKeys.uniformMonitor: false,
        AccessKeys.uniformMonitorAdmin: false,
        for (final k in AccessKeys.partnerDetailTabKeys) k: true,
      };

  static Map<String, dynamic> forRole(UserRole role) {
    switch (role) {
      case UserRole.leder:
        return departmentLeader();
      case UserRole.admin:
        return companyAdmin();
      case UserRole.superadmin:
        return AccessKeys.allOn();
      case UserRole.samarbeidspartner:
        return {
          ...AccessKeys.allOff(),
          AccessKeys.dashboard: true,
          AccessKeys.more: true,
          AccessKeys.partners: true,
          AccessKeys.profil: true,
        };
      case UserRole.ansatt:
        return employee();
    }
  }

  static String presetTitle(UserRole role) {
    switch (role) {
      case UserRole.ansatt:
        return 'Ansatt (kun egne data)';
      case UserRole.leder:
        return 'Avdelingsleder (egen avdeling)';
      case UserRole.admin:
        return 'Administrator';
      case UserRole.superadmin:
        return 'Superadmin – alt på';
      case UserRole.samarbeidspartner:
        return 'Samarbeidspartner';
    }
  }
}
