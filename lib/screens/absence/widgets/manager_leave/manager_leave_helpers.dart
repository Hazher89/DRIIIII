import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/absence/absence_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/absence.dart';
import '../../../../models/user_profile.dart';

enum ManagerLeaveTodayStatus {
  paJobb,
  ferie,
  sykemeldt,
  egenmelding,
  syktBarn,
  permisjon,
  annet,
}

enum ManagerLeaveStatusFilter { alle, paJobb, ferie, sykemeldt }

extension ManagerLeaveTodayStatusX on ManagerLeaveTodayStatus {
  String get label {
    switch (this) {
      case ManagerLeaveTodayStatus.paJobb:
        return '';
      case ManagerLeaveTodayStatus.ferie:
        return 'Ferie';
      case ManagerLeaveTodayStatus.sykemeldt:
        return 'Sykemeldt';
      case ManagerLeaveTodayStatus.egenmelding:
        return 'Egenmelding';
      case ManagerLeaveTodayStatus.syktBarn:
        return 'Sykt barn';
      case ManagerLeaveTodayStatus.permisjon:
        return 'Permisjon';
      case ManagerLeaveTodayStatus.annet:
        return 'Fravær';
    }
  }

  Color get color {
    switch (this) {
      case ManagerLeaveTodayStatus.paJobb:
        return DriftProTheme.success;
      case ManagerLeaveTodayStatus.ferie:
        return DriftProTheme.absenceVacation;
      case ManagerLeaveTodayStatus.sykemeldt:
        return const Color(0xFFEA580C);
      case ManagerLeaveTodayStatus.egenmelding:
        return DriftProTheme.warning;
      case ManagerLeaveTodayStatus.syktBarn:
        return DriftProTheme.absenceSickChild;
      case ManagerLeaveTodayStatus.permisjon:
        return DriftProTheme.absenceLeave;
      case ManagerLeaveTodayStatus.annet:
        return DriftProTheme.info;
    }
  }
}

class ManagerLeaveHelpers {
  ManagerLeaveHelpers._();

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static int daysFor(Absence a) {
    if (a.type == AbsenceType.ferie) {
      return a.vacationDayCount ??
          AbsenceService.vacationDayCount(a.startDate, a.endDate);
    }
    return a.totalDays ?? (a.endDate.difference(a.startDate).inDays + 1);
  }

  static bool coversDate(Absence a, DateTime day) {
    final t = dayOnly(day);
    final s = dayOnly(a.startDate);
    final e = dayOnly(a.endDate);
    return !t.isBefore(s) && !t.isAfter(e);
  }

  static bool isApprovedActiveToday(Absence a, [DateTime? now]) {
    if (a.status != AbsenceStatus.godkjent) return false;
    return coversDate(a, now ?? DateTime.now());
  }

  static ManagerLeaveTodayStatus todayStatusFor(
    List<Absence> absences, [
    DateTime? now,
  ]) {
    final today = now ?? DateTime.now();
    final active = absences.where((a) => isApprovedActiveToday(a, today)).toList();
    if (active.isEmpty) return ManagerLeaveTodayStatus.paJobb;

    Absence? pick(AbsenceType type) {
      for (final a in active) {
        if (a.type == type) return a;
      }
      return null;
    }

    if (pick(AbsenceType.sykmelding) != null) {
      return ManagerLeaveTodayStatus.sykemeldt;
    }
    if (pick(AbsenceType.ferie) != null) return ManagerLeaveTodayStatus.ferie;
    if (pick(AbsenceType.egenmelding) != null) {
      return ManagerLeaveTodayStatus.egenmelding;
    }
    if (pick(AbsenceType.syktBarn) != null) {
      return ManagerLeaveTodayStatus.syktBarn;
    }
    if (pick(AbsenceType.permisjon) != null) {
      return ManagerLeaveTodayStatus.permisjon;
    }
    return ManagerLeaveTodayStatus.annet;
  }

  static Absence? nextPlannedAbsence(List<Absence> absences, [DateTime? now]) {
    final t = dayOnly(now ?? DateTime.now());
    final upcoming = absences
        .where((a) =>
            (a.status == AbsenceStatus.godkjent ||
                a.status == AbsenceStatus.ventende) &&
            !dayOnly(a.endDate).isBefore(t))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    for (final a in upcoming) {
      if (dayOnly(a.startDate).isAfter(t)) return a;
      if (coversDate(a, t) && a.status == AbsenceStatus.godkjent) {
        // ongoing — prefer true "next" after today
        continue;
      }
      if (dayOnly(a.startDate).isAtSameMomentAs(t) ||
          dayOnly(a.startDate).isAfter(t)) {
        return a;
      }
    }

    final after = upcoming.where((a) => dayOnly(a.startDate).isAfter(t)).toList();
    return after.isEmpty ? null : after.first;
  }

  /// Neste planlagte fravær inkl. pågående (for tabelltekst).
  static Absence? nextOrOngoingAbsence(List<Absence> absences, [DateTime? now]) {
    final t = dayOnly(now ?? DateTime.now());
    final candidates = absences
        .where((a) =>
            (a.status == AbsenceStatus.godkjent ||
                a.status == AbsenceStatus.ventende) &&
            !dayOnly(a.endDate).isBefore(t))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return candidates.isEmpty ? null : candidates.first;
  }

  static int isoWeekOf(DateTime date) {
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final firstDay = DateTime(thursday.year);
    return 1 + ((thursday.difference(firstDay).inDays) / 7).floor();
  }

  static String formatPeriod(Absence a) {
    final sameYear = a.startDate.year == a.endDate.year;
    final start = DateFormat(sameYear ? 'd. MMM' : 'd. MMM yyyy', 'nb_NO')
        .format(a.startDate);
    final end = DateFormat('d. MMM yyyy', 'nb_NO').format(a.endDate);
    return '$start – $end';
  }

  static String formatShortPeriod(Absence a) {
    final start = DateFormat('d. MMM', 'nb_NO').format(a.startDate);
    final end = DateFormat('d. MMM', 'nb_NO').format(a.endDate);
    return '$start – $end';
  }

  static String nextAbsenceLabel(Absence a) {
    final week = isoWeekOf(a.startDate);
    final days = daysFor(a);
    final pending = a.status == AbsenceStatus.ventende ? ' (venter)' : '';
    return 'Uke $week: ${a.type.label} ($days dager)$pending';
  }

  static Color colorForType(AbsenceType type) {
    switch (type) {
      case AbsenceType.ferie:
        return DriftProTheme.absenceVacation;
      case AbsenceType.egenmelding:
        return DriftProTheme.absenceSickSelf;
      case AbsenceType.syktBarn:
        return DriftProTheme.absenceSickChild;
      case AbsenceType.permisjon:
        return DriftProTheme.absenceLeave;
      case AbsenceType.sykmelding:
        return DriftProTheme.absenceSickNote;
    }
  }

  static List<UserProfile> employeesInScope({
    required List<UserProfile> teamProfiles,
    required UserProfile? leader,
    bool excludeSelf = true,
  }) {
    var list = teamProfiles.where((p) => !p.isPartnerPortalUser).toList();
    if (excludeSelf && leader != null) {
      list = list.where((p) => p.id != leader.id).toList();
    }
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  }

  static List<Absence> absencesNextWeek(
    List<Absence> absences, [
    DateTime? now,
  ]) {
    final today = dayOnly(now ?? DateTime.now());
    final weekday = today.weekday; // 1=Mon
    final nextMonday = today.add(Duration(days: 8 - weekday));
    final nextSunday = nextMonday.add(const Duration(days: 6));
    return absences.where((a) {
      if (a.status != AbsenceStatus.godkjent &&
          a.status != AbsenceStatus.ventende) {
        return false;
      }
      final s = dayOnly(a.startDate);
      final e = dayOnly(a.endDate);
      return !e.isBefore(nextMonday) && !s.isAfter(nextSunday);
    }).toList();
  }

  static Set<String> uniqueUsers(Iterable<Absence> absences) =>
      absences.map((a) => a.userId).toSet();
}
