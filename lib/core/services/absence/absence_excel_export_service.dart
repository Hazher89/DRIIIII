import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../constants/leave_rules.dart';
import '../../utils/bytes_download.dart';
import '../../utils/business_days.dart';
import 'absence_service.dart';
import 'employee_leave_stats.dart';

enum AbsenceExportTypeFilter {
  alle,
  ferie,
  egenmelding,
  syktBarn,
  sykmelding,
  permisjon,
}

extension AbsenceExportTypeFilterX on AbsenceExportTypeFilter {
  String get label {
    switch (this) {
      case AbsenceExportTypeFilter.alle:
        return 'Alle typer';
      case AbsenceExportTypeFilter.ferie:
        return 'Ferie';
      case AbsenceExportTypeFilter.egenmelding:
        return 'Egenmelding';
      case AbsenceExportTypeFilter.syktBarn:
        return 'Sykt barn';
      case AbsenceExportTypeFilter.sykmelding:
        return 'Sykmelding';
      case AbsenceExportTypeFilter.permisjon:
        return 'Permisjon';
    }
  }

  bool matches(AbsenceType type) {
    switch (this) {
      case AbsenceExportTypeFilter.alle:
        return true;
      case AbsenceExportTypeFilter.ferie:
        return type == AbsenceType.ferie;
      case AbsenceExportTypeFilter.egenmelding:
        return type == AbsenceType.egenmelding;
      case AbsenceExportTypeFilter.syktBarn:
        return type == AbsenceType.syktBarn;
      case AbsenceExportTypeFilter.sykmelding:
        return type == AbsenceType.sykmelding;
      case AbsenceExportTypeFilter.permisjon:
        return type == AbsenceType.permisjon;
    }
  }
}

/// Polert Excel-eksport for fravær/ferie — per ansatt eller hele teamet.
abstract final class AbsenceExcelExportService {
  static Future<void> export({
    required List<UserProfile> employees,
    required List<Absence> absences,
    required List<AbsenceQuota> quotas,
    required Map<String, String> departmentNames,
    required Map<String, String> approverNames,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required AbsenceExportTypeFilter typeFilter,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
    String? companyName,
    String? singleEmployeeId,
  }) async {
    final scopedEmployees = singleEmployeeId == null
        ? employees.where((e) => !e.isPartnerPortalUser).toList()
        : employees.where((e) => e.id == singleEmployeeId).toList();
    scopedEmployees.sort((a, b) => a.fullName.compareTo(b.fullName));

    final excel = Excel.createExcel();
    final overview = excel['Oversikt'];
    final details = excel['Detaljer'];
    try {
      excel.delete('Sheet1');
    } catch (_) {}

    final df = DateFormat('dd.MM.yyyy');
    final generated = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
    final title = companyName?.trim().isNotEmpty == true
        ? 'Fraværsoversikt — ${companyName!.trim()}'
        : 'Fraværsoversikt DriftPro';
    final periodLabel =
        '${df.format(rangeStart)} – ${df.format(rangeEnd)} · ${typeFilter.label}';

    overview.appendRow([TextCellValue(title)]);
    overview.appendRow([TextCellValue(periodLabel)]);
    overview.appendRow([TextCellValue('Generert $generated')]);
    overview.appendRow([TextCellValue('')]);
    overview.appendRow([
      TextCellValue('Ansatt'),
      TextCellValue('Avdeling'),
      TextCellValue('På jobb / status'),
      TextCellValue('Ferie brukt'),
      TextCellValue('Ferie igjen'),
      TextCellValue('Ferie totalt'),
      TextCellValue('Ferie %'),
      TextCellValue('Egenmelding dager'),
      TextCellValue('Egenmelding tilfeller'),
      TextCellValue('Sykt barn dager'),
      TextCellValue('Sykmelding dager'),
      TextCellValue('Fraværsdager totalt'),
      TextCellValue('Fravær %'),
      TextCellValue('Antall perioder'),
    ]);

    details.appendRow([
      TextCellValue('Ansatt'),
      TextCellValue('Avdeling'),
      TextCellValue('Type'),
      TextCellValue('Fra'),
      TextCellValue('Til'),
      TextCellValue('Dager'),
      TextCellValue('Status'),
      TextCellValue('Søkt dato'),
      TextCellValue('Godkjent av'),
      TextCellValue('Godkjent dato'),
      TextCellValue('Kommentar'),
      TextCellValue('Beslutningskommentar'),
    ]);

    bool inRange(Absence a) {
      final s = BusinessDays.dayOnly(a.startDate);
      final e = BusinessDays.dayOnly(a.endDate);
      return !e.isBefore(rangeStart) && !s.isAfter(rangeEnd);
    }

    int daysFor(Absence a) {
      if (a.type == AbsenceType.ferie) {
        return a.vacationDayCount ??
            AbsenceService.vacationDayCount(a.startDate, a.endDate);
      }
      return a.totalDays ?? AbsenceService.dayCount(a.startDate, a.endDate);
    }

    AbsenceQuota? quotaFor(String userId) {
      final year = rangeStart.year;
      for (final q in quotas) {
        if (q.userId == userId && q.year == year) return q;
      }
      return null;
    }

    for (final emp in scopedEmployees) {
      final empAbs = absences
          .where((a) =>
              a.userId == emp.id && inRange(a) && typeFilter.matches(a.type))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

      final allInRange =
          absences.where((a) => a.userId == emp.id && inRange(a)).toList();
      final quota = quotaFor(emp.id);
      final stats = EmployeeLeaveSnapshot.compute(
        employee: emp,
        employeeAbsences: allInRange,
        quota: quota,
        company: company,
        referenceDate: rangeEnd.isBefore(DateTime.now())
            ? rangeEnd
            : DateTime.now(),
      );

      final sykmeldingDays = allInRange
          .where((a) =>
              a.type == AbsenceType.sykmelding &&
              a.status == AbsenceStatus.godkjent)
          .fold<int>(0, (sum, a) => sum + daysFor(a));

      final dept = emp.departmentId == null
          ? ''
          : (departmentNames[emp.departmentId!] ?? '');
      final workDays = BusinessDays.countInRange(rangeStart, rangeEnd);
      final absencePct = workDays <= 0
          ? 0.0
          : (stats.totalFravaerDager / workDays * 100).clamp(0, 100);
      final feriePct = stats.ferieTotal <= 0
          ? 0.0
          : (stats.ferieUsed / stats.ferieTotal * 100).clamp(0, 100);

      overview.appendRow([
        TextCellValue(emp.fullName),
        TextCellValue(dept),
        TextCellValue(empAbs.any((a) {
          final t = BusinessDays.dayOnly(DateTime.now());
          return a.status == AbsenceStatus.godkjent &&
              !t.isBefore(BusinessDays.dayOnly(a.startDate)) &&
              !t.isAfter(BusinessDays.dayOnly(a.endDate));
        })
            ? 'Borte'
            : 'På jobb'),
        IntCellValue(stats.ferieUsed),
        IntCellValue(stats.ferieRemaining),
        IntCellValue(stats.ferieTotal),
        TextCellValue('${feriePct.toStringAsFixed(0)}%'),
        IntCellValue(stats.egenDaysTotal),
        IntCellValue(stats.egenTilfeller),
        IntCellValue(stats.syktDays),
        IntCellValue(sykmeldingDays),
        IntCellValue(stats.totalFravaerDager + sykmeldingDays),
        TextCellValue('${absencePct.toStringAsFixed(1)}%'),
        IntCellValue(empAbs.length),
      ]);

      if (empAbs.isEmpty) {
        details.appendRow([
          TextCellValue(emp.fullName),
          TextCellValue(dept),
          TextCellValue(typeFilter.label),
          TextCellValue(''),
          TextCellValue(''),
          IntCellValue(0),
          TextCellValue('Ingen i perioden'),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
        ]);
        continue;
      }

      for (final a in empAbs) {
        final approver = a.approvedBy == null
            ? ''
            : (approverNames[a.approvedBy!] ?? a.approvedBy!);
        details.appendRow([
          TextCellValue(emp.fullName),
          TextCellValue(dept),
          TextCellValue(a.type.label),
          TextCellValue(df.format(a.startDate)),
          TextCellValue(df.format(a.endDate)),
          IntCellValue(daysFor(a)),
          TextCellValue(a.status.label),
          TextCellValue(
            a.createdAt == null ? '' : df.format(a.createdAt!),
          ),
          TextCellValue(approver),
          TextCellValue(
            a.approvedAt == null ? '' : df.format(a.approvedAt!),
          ),
          TextCellValue(a.comment ?? ''),
          TextCellValue(a.decisionComment ?? ''),
        ]);
      }
    }

    final bytes = excel.encode();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Kunne ikke lage Excel-fil');
    }

    final who = singleEmployeeId == null
        ? 'alle'
        : (scopedEmployees.isEmpty
            ? 'ansatt'
            : scopedEmployees.first.fullName
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9æøå]+'), '_'));
    final file =
        'fravaer_${typeFilter.name}_${df.format(rangeStart)}_${df.format(rangeEnd)}_$who.xlsx'
            .replaceAll('.', '-');

    await downloadBytes(
      Uint8List.fromList(bytes),
      file,
      mime:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }
}
