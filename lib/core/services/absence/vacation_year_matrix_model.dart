import 'package:intl/intl.dart';

import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../services/absence/absence_service.dart';

class VacationWeekColumn {
  const VacationWeekColumn({
    required this.week,
    required this.monday,
    required this.month,
  });

  final int week;
  final DateTime monday;
  final int month;
}

class VacationSpan {
  const VacationSpan({
    required this.start,
    required this.end,
    required this.workDays,
    required this.status,
    required this.weekNumbers,
    required this.absenceIds,
  });

  final DateTime start;
  final DateTime end;
  final int workDays;
  final AbsenceStatus status;
  final List<int> weekNumbers;
  final List<String> absenceIds;

  String get periodLabel =>
      '${DateFormat('dd.MM').format(start)}–${DateFormat('dd.MM.yyyy').format(end)}';

  String get statusLabel => status.label;

  String get weekLabel =>
      weekNumbers.isEmpty ? '' : 'U${weekNumbers.join(', U')}';

  String tooltip(String employeeName) {
    final pending = status == AbsenceStatus.ventende ? ' (ventende)' : '';
    return '$employeeName · $workDays virkedager$pending\n$periodLabel';
  }
}

class VacationEmployeeRow {
  const VacationEmployeeRow({
    required this.userId,
    required this.name,
    required this.spans,
    required this.daysInWeek,
    required this.totalWorkDays,
  });

  final String userId;
  final String name;
  final List<VacationSpan> spans;
  final Map<int, int> daysInWeek;
  final int totalWorkDays;
}

class VacationYearMatrixModel {
  const VacationYearMatrixModel({
    required this.year,
    required this.weeks,
    required this.employeeRows,
    required this.monthSpans,
  });

  final int year;
  final List<VacationWeekColumn> weeks;
  final List<VacationEmployeeRow> employeeRows;

  /// Måned → antall ukekolonner (for header colspan).
  final List<({int month, int weekCount, String label})> monthSpans;

  static VacationYearMatrixModel build({
    required int year,
    required List<UserProfile> employees,
    required List<Absence> vacations,
  }) {
    final weeks = _weeksOfYear(year);
    final monthSpans = <({int month, int weekCount, String label})>[];
    if (weeks.isNotEmpty) {
      var cur = weeks.first.month;
      var count = 0;
      for (final w in weeks) {
        if (w.month != cur) {
          monthSpans.add((
            month: cur,
            weekCount: count,
            label: _monthShort(cur),
          ));
          cur = w.month;
          count = 0;
        }
        count++;
      }
      monthSpans.add((month: cur, weekCount: count, label: _monthShort(cur)));
    }

    final byUser = <String, List<Absence>>{};
    for (final a in vacations) {
      if (a.type != AbsenceType.ferie) continue;
      if (a.status == AbsenceStatus.avvist) continue;
      if (a.endDate.year < year || a.startDate.year > year) continue;
      byUser.putIfAbsent(a.userId, () => []).add(a);
    }

    final sortedEmployees = [...employees]
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

    final rows = <VacationEmployeeRow>[];
    for (final emp in sortedEmployees) {
      final list = byUser[emp.id] ?? const <Absence>[];
      final spans = _mergeSpans(list, year);
      final daysInWeek = <int, int>{};
      for (final w in weeks) {
        var n = 0;
        for (final a in list) {
          n += _workDaysOverlap(a, w.monday, year);
        }
        if (n > 0) daysInWeek[w.week] = n;
      }
      final total = spans.fold<int>(0, (s, e) => s + e.workDays);
      rows.add(
        VacationEmployeeRow(
          userId: emp.id,
          name: emp.fullName,
          spans: spans,
          daysInWeek: daysInWeek,
          totalWorkDays: total,
        ),
      );
    }

    return VacationYearMatrixModel(
      year: year,
      weeks: weeks,
      employeeRows: rows,
      monthSpans: monthSpans,
    );
  }

  static List<VacationSpan> _mergeSpans(List<Absence> list, int year) {
    if (list.isEmpty) return const [];
    final sorted = [...list]..sort((a, b) => a.startDate.compareTo(b.startDate));
    final out = <VacationSpan>[];

    DateTime clampStart(DateTime d) =>
        d.isBefore(DateTime(year, 1, 1)) ? DateTime(year, 1, 1) : d;
    DateTime clampEnd(DateTime d) =>
        d.isAfter(DateTime(year, 12, 31)) ? DateTime(year, 12, 31) : d;

    var curStart = clampStart(sorted.first.startDate);
    var curEnd = clampEnd(sorted.first.endDate);
    var status = sorted.first.status;
    final ids = <String>[sorted.first.id];

    for (var i = 1; i < sorted.length; i++) {
      final a = sorted[i];
      final s = clampStart(a.startDate);
      final e = clampEnd(a.endDate);
      // Sammenhengende / overlappende (inkl. helg mellom) → slå sammen.
      final gap = s.difference(curEnd).inDays;
      if (gap <= 3) {
        if (e.isAfter(curEnd)) curEnd = e;
        if (a.status == AbsenceStatus.ventende) status = AbsenceStatus.ventende;
        ids.add(a.id);
      } else {
        out.add(_span(curStart, curEnd, status, ids));
        curStart = s;
        curEnd = e;
        status = a.status;
        ids
          ..clear()
          ..add(a.id);
      }
    }
    out.add(_span(curStart, curEnd, status, ids));
    return out;
  }

  static VacationSpan _span(
    DateTime start,
    DateTime end,
    AbsenceStatus status,
    List<String> ids,
  ) {
    final weeks = <int>{};
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      weeks.add(isoWeekNumber(d));
    }
    final sortedWeeks = weeks.toList()..sort();
    return VacationSpan(
      start: start,
      end: end,
      workDays: AbsenceService.vacationDayCount(start, end),
      status: status,
      weekNumbers: sortedWeeks,
      absenceIds: List.unmodifiable(ids),
    );
  }

  static int _workDaysOverlap(Absence a, DateTime weekMonday, int year) {
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31);
    var start = a.startDate.isAfter(weekMonday) ? a.startDate : weekMonday;
    final weekEnd = weekMonday.add(const Duration(days: 6));
    var end = a.endDate.isBefore(weekEnd) ? a.endDate : weekEnd;
    if (start.isBefore(yearStart)) start = yearStart;
    if (end.isAfter(yearEnd)) end = yearEnd;
    if (end.isBefore(start)) return 0;
    return AbsenceService.vacationDayCount(start, end);
  }

  static List<VacationWeekColumn> _weeksOfYear(int year) {
    // ISO: uke 1 er uken med årets første torsdag.
    final jan4 = DateTime(year, 1, 4);
    final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
    final out = <VacationWeekColumn>[];
    var monday = week1Monday;
    while (true) {
      final thursday = monday.add(const Duration(days: 3));
      if (thursday.year > year) break;
      if (thursday.year < year) {
        monday = monday.add(const Duration(days: 7));
        continue;
      }
      out.add(
        VacationWeekColumn(
          week: isoWeekNumber(thursday),
          monday: monday,
          month: thursday.month,
        ),
      );
      monday = monday.add(const Duration(days: 7));
    }
    return out;
  }

  static int isoWeekNumber(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final thursday = d.add(Duration(days: 4 - (d.weekday == DateTime.sunday ? 7 : d.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week1Monday =
        firstThursday.subtract(Duration(days: firstThursday.weekday - 1));
    return thursday.difference(week1Monday).inDays ~/ 7 + 1;
  }

  static String _monthShort(int m) {
    const names = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return names[m];
  }

  /// Span som dekker denne uken (for tooltip).
  VacationSpan? spanForWeek(VacationEmployeeRow row, int week) {
    for (final s in row.spans) {
      if (s.weekNumbers.contains(week)) return s;
    }
    return null;
  }
}
