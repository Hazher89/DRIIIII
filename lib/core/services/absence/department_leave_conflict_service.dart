import '../../../models/absence.dart';
import 'absence_service.dart';

/// Overlapp mellom en søknad og annet fravær i samme avdeling.
class DepartmentLeaveOverlap {
  final Absence other;
  final DateTime overlapStart;
  final DateTime overlapEnd;
  final int overlapDays;

  const DepartmentLeaveOverlap({
    required this.other,
    required this.overlapStart,
    required this.overlapEnd,
    required this.overlapDays,
  });

  bool get isApproved => other.status == AbsenceStatus.godkjent;
  bool get isPending => other.status == AbsenceStatus.ventende;
  bool get isVacation => other.type == AbsenceType.ferie;
}

/// Smart kollega-/avdelingssjekk før ferie godkjennes.
class DepartmentLeaveConflictService {
  DepartmentLeaveConflictService._();

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static bool datesOverlap(
    DateTime startA,
    DateTime endA,
    DateTime startB,
    DateTime endB,
  ) {
    final a0 = _dateOnly(startA);
    final a1 = _dateOnly(endA);
    final b0 = _dateOnly(startB);
    final b1 = _dateOnly(endB);
    return !(a1.isBefore(b0) || a0.isAfter(b1));
  }

  /// Finner overlappende fravær i samme avdeling (ekskl. avvist og egen søker).
  static List<DepartmentLeaveOverlap> findOverlaps({
    required String departmentId,
    required DateTime startDate,
    required DateTime endDate,
    required List<Absence> pool,
    String? excludeUserId,
    String? excludeAbsenceId,
    bool vacationOnly = false,
  }) {
    final out = <DepartmentLeaveOverlap>[];

    for (final other in pool) {
      if (other.departmentId != departmentId) continue;
      if (excludeUserId != null && other.userId == excludeUserId) continue;
      if (excludeAbsenceId != null && other.id == excludeAbsenceId) continue;
      if (other.status == AbsenceStatus.avvist) continue;
      if (vacationOnly && other.type != AbsenceType.ferie) continue;
      if (!datesOverlap(startDate, endDate, other.startDate, other.endDate)) {
        continue;
      }

      final oStart = _dateOnly(other.startDate);
      final oEnd = _dateOnly(other.endDate);
      final rStart = _dateOnly(startDate);
      final rEnd = _dateOnly(endDate);
      final overlapStart = oStart.isAfter(rStart) ? oStart : rStart;
      final overlapEnd = oEnd.isBefore(rEnd) ? oEnd : rEnd;
      final days = AbsenceService.dayCount(overlapStart, overlapEnd);

      out.add(DepartmentLeaveOverlap(
        other: other,
        overlapStart: overlapStart,
        overlapEnd: overlapEnd,
        overlapDays: days,
      ));
    }

    out.sort((a, b) {
      if (a.isApproved != b.isApproved) {
        return a.isApproved ? -1 : 1;
      }
      return a.other.startDate.compareTo(b.other.startDate);
    });
    return out;
  }

  static List<DepartmentLeaveOverlap> forRequest(
    Absence request,
    List<Absence> pool, {
    bool vacationOnly = false,
  }) {
    if (request.departmentId == null) return [];
    return findOverlaps(
      departmentId: request.departmentId!,
      startDate: request.startDate,
      endDate: request.endDate,
      pool: pool,
      excludeUserId: request.userId,
      excludeAbsenceId: request.id,
      vacationOnly: vacationOnly,
    );
  }

  static List<DepartmentLeaveOverlap> approvedVacation(
    List<DepartmentLeaveOverlap> overlaps,
  ) =>
      overlaps.where((o) => o.isApproved && o.isVacation).toList();

  static List<DepartmentLeaveOverlap> pendingAny(
    List<DepartmentLeaveOverlap> overlaps,
  ) =>
      overlaps.where((o) => o.isPending).toList();

  static bool hasCriticalOverlap(List<DepartmentLeaveOverlap> overlaps) =>
      approvedVacation(overlaps).isNotEmpty;
}
