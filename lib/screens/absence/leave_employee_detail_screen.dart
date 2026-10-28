import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/company_principals.dart';
import '../../core/constants/leave_rules.dart';
import '../../core/services/absence/absence_service.dart';
import '../../core/services/absence/employee_leave_stats.dart';
import '../../core/services/absence/leave_period_usage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/business_days.dart';
import '../../core/utils/leave_period_window.dart';
import '../../core/utils/leave_usage_colors.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';
import 'new_absence_screen.dart';
import 'widgets/absence_excel_export_sheet.dart';
import 'widgets/leave_employee_kpi_widgets.dart';
import 'widgets/leave_period_scope.dart';
import 'widgets/leave_quick_actions.dart';
import 'widgets/leave_type_dates_sheet.dart';

/// Full side for én ansatt — avansert saldo, diagram, tips og historikk.
class LeaveEmployeeDetailScreen extends StatefulWidget {
  const LeaveEmployeeDetailScreen({
    super.key,
    required this.employee,
    required this.quotaOf,
    required this.company,
    required this.selectedYear,
    required this.absencesOf,
    required this.departmentNames,
    required this.canRegister,
    required this.canEditQuota,
    this.onEditQuota,
    this.onAbsenceTap,
    this.onChanged,
    this.onYearChanged,
    this.teamProfiles = const [],
    this.teamQuotas = const [],
    this.allAbsences = const [],
    this.approverNames = const {},
    this.companyName,
  });

  final UserProfile employee;
  final AbsenceQuota? Function() quotaOf;
  final CompanyLeaveSettings company;
  final int selectedYear;
  final List<Absence> Function() absencesOf;
  final Map<String, String> departmentNames;
  final bool canRegister;
  final bool canEditQuota;
  final VoidCallback? onEditQuota;
  final void Function(Absence absence)? onAbsenceTap;
  final Future<void> Function()? onChanged;
  final ValueChanged<int>? onYearChanged;
  final List<UserProfile> teamProfiles;
  final List<AbsenceQuota> teamQuotas;
  final List<Absence> allAbsences;
  final Map<String, String> approverNames;
  final String? companyName;

  @override
  State<LeaveEmployeeDetailScreen> createState() =>
      _LeaveEmployeeDetailScreenState();
}

class _LeaveEmployeeDetailScreenState extends State<LeaveEmployeeDetailScreen> {
  late LeavePeriodScope _scope;

  @override
  void initState() {
    super.initState();
    _scope = LeavePeriodScope.year(widget.selectedYear);
  }

  @override
  void didUpdateWidget(covariant LeaveEmployeeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear &&
        _scope.mode == LeavePeriodMode.year &&
        _scope.year != widget.selectedYear) {
      _scope = LeavePeriodScope.year(widget.selectedYear);
    }
  }

  Future<void> _openRegister() async {
    final type = await showLeaveTypePickerSheet(
      context,
      employeeName: widget.employee.fullName,
    );
    if (type == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewAbsenceScreen(
          type: type,
          lockedEmployee: widget.employee,
        ),
      ),
    );
    if (saved == true) {
      await widget.onChanged?.call();
      if (mounted) setState(() {});
    }
  }

  void _onScopeChanged(LeavePeriodScope scope) {
    setState(() => _scope = scope);
    widget.onYearChanged?.call(scope.year);
  }

  List<Absence> get _allEmployeeAbsences => widget.absencesOf();

  List<Absence> get _scopedAbsences => _scope.filter(_allEmployeeAbsences);

  EmployeeLeaveSnapshot _stats(AbsenceQuota? quota) {
    final usage = LeavePeriodUsageService.computeForWindow(
      absences: _allEmployeeAbsences,
      window: LeavePeriodWindow(
        periodStart: _scope.rangeStart,
        periodEnd: _scope.rangeEnd,
      ),
    );
    return EmployeeLeaveSnapshot.compute(
      employee: widget.employee,
      employeeAbsences: _allEmployeeAbsences,
      quota: quota,
      company: widget.company,
      referenceDate: _scope.referenceDate,
      periodUsageOverride: usage,
    );
  }

  int _typeDays(AbsenceType type) {
    return EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
      absences: _scopedAbsences,
      rangeStart: _scope.rangeStart,
      rangeEnd: _scope.referenceDate.isBefore(_scope.rangeEnd)
          ? _scope.referenceDate
          : _scope.rangeEnd,
      types: {type},
    );
  }

  Future<void> _showTypeDates(AbsenceType type, String title) {
    final list = _scopedAbsences.where((a) => a.type == type).toList();
    return showLeaveTypeDatesSheet(
      context,
      title: title,
      absences: list,
      approverNames: widget.approverNames,
      onTap: widget.onAbsenceTap,
    );
  }

  Future<void> _exportExcel() {
    final employees = widget.teamProfiles.isEmpty
        ? [widget.employee]
        : widget.teamProfiles;
    final absences =
        widget.allAbsences.isEmpty ? _allEmployeeAbsences : widget.allAbsences;
    final quotas = widget.teamQuotas.isEmpty && widget.quotaOf() != null
        ? [widget.quotaOf()!]
        : widget.teamQuotas;
    return showAbsenceExcelExportSheet(
      context,
      employees: employees,
      absences: absences,
      quotas: quotas,
      departmentNames: widget.departmentNames,
      approverNames: widget.approverNames,
      initialScope: _scope,
      company: widget.company,
      companyName: widget.companyName,
      lockedEmployeeId: widget.employee.id,
    );
  }

  List<String> _smartTips(EmployeeLeaveSnapshot stats) {
    final tips = <String>[];
    if (stats.egenLevel == LeaveUsageLevel.critical) {
      tips.add(
        'Egenmelding er brukt opp (${stats.egenDaysTotal}/${stats.egenMax} d · '
        '${stats.egenTilfeller}/${stats.egenTilfellerMax} tilf.). '
        'Videre fravær krever som hovedregel sykmelding.',
      );
    } else if (stats.egenLevel == LeaveUsageLevel.warning) {
      tips.add(
        'Egenmelding nærmer seg taket '
        '(${stats.egenDaysTotal}/${stats.egenMax} d). Planlegg oppfølging.',
      );
    }
    if (stats.syktLevel == LeaveUsageLevel.critical) {
      tips.add(
        'Sykt barn / omsorgspenger er brukt opp '
        '(${stats.syktDays}/${stats.syktMax} d). Sjekk rettigheter for flere barn.',
      );
    } else if (stats.syktLevel == LeaveUsageLevel.warning) {
      tips.add(
        'Sykt barn nærmer seg kvoten (${stats.syktDays}/${stats.syktMax} d).',
      );
    }
    if (stats.ferieLevel == LeaveUsageLevel.critical) {
      tips.add('Ingen feriedager igjen i ${_scope.year}.');
    } else if (stats.ferieRemaining <= 5 && stats.ferieTotal > 0) {
      tips.add(
        'Kun ${stats.ferieRemaining} feriedager igjen — vurder hovedferie/overføring.',
      );
    }
    if (stats.sykmeldingDays >= 16) {
      tips.add(
        'Langvarig sykmelding (${stats.sykmeldingDays} d). '
        'Husk oppfølgingsplan og dialog (aml. § 4-6).',
      );
    }
    if (widget.employee.hireDate == null) {
      tips.add(
        'Sett ansettelsesdato for korrekt 12-månedersperiode for egenmelding/sykt barn.',
      );
    }
    if (tips.isEmpty) {
      tips.add(
        'Saldoene er innenfor grensene. Godkjenn ferie i god tid og unngå overlapping.',
      );
    }
    return tips;
  }

  List<double> _monthlyDays() {
    final year = _scope.year;
    final from = DateTime(year, 1, 1);
    final to = _scope.mode == LeavePeriodMode.year
        ? (_scope.referenceDate.year == year
            ? _scope.referenceDate
            : DateTime(year, 12, 31))
        : _scope.rangeEnd;
    final months = List<double>.filled(12, 0);
    final pool = _allEmployeeAbsences;
    for (var m = 0; m < 12; m++) {
      final ms = DateTime(year, m + 1, 1);
      final me = DateTime(year, m + 2, 0);
      final s = ms.isBefore(from) ? from : ms;
      var e = me.isAfter(to) ? to : me;
      if (_scope.mode == LeavePeriodMode.range) {
        if (me.isBefore(_scope.rangeStart) || ms.isAfter(_scope.rangeEnd)) {
          continue;
        }
        final rs = ms.isBefore(_scope.rangeStart) ? _scope.rangeStart : ms;
        final re = me.isAfter(_scope.rangeEnd) ? _scope.rangeEnd : me;
        e = re.isAfter(to) ? to : re;
        months[m] = EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
          absences: pool,
          rangeStart: rs,
          rangeEnd: e,
        ).toDouble();
      } else {
        if (e.isBefore(s)) continue;
        months[m] = EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
          absences: pool,
          rangeStart: s,
          rangeEnd: e,
        ).toDouble();
      }
    }
    return months;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    final quota = widget.quotaOf();
    final scoped = [..._scopedAbsences]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final stats = _stats(quota);
    final rate = stats.absenceRatePercent(_scope.referenceDate);
    final rateLevel = stats.absenceRateLevel(_scope.referenceDate);
    final rateColor =
        LeaveUsageColors.colorFor(rateLevel, DriftProTheme.absenceSickSelf);
    final sykDays = _typeDays(AbsenceType.sykmelding);
    final permDays = _typeDays(AbsenceType.permisjon);
    final monthly = _monthlyDays();
    final tips = _smartTips(stats);
    final dept = widget.employee.departmentId != null
        ? widget.departmentNames[widget.employee.departmentId!]
        : null;
    final onLeaveToday = scoped.any((a) {
      if (a.status != AbsenceStatus.godkjent) return false;
      final t = BusinessDays.dayOnly(DateTime.now());
      final s = BusinessDays.dayOnly(a.startDate);
      final e = BusinessDays.dayOnly(a.endDate);
      return !t.isBefore(s) && !t.isAfter(e);
    });

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(widget.employee.fullName),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Flere valg',
            onSelected: (v) async {
              switch (v) {
                case 'quota':
                  widget.onEditQuota?.call();
                  await widget.onChanged?.call();
                  if (mounted) setState(() {});
                case 'export':
                  await _exportExcel();
              }
            },
            itemBuilder: (_) => [
              if (widget.canEditQuota && widget.onEditQuota != null)
                const PopupMenuItem(
                  value: 'quota',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune_rounded),
                    title: Text('Rediger feriekvote'),
                  ),
                ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Eksporter Excel'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.canRegister
          ? FloatingActionButton.extended(
              onPressed: _openRegister,
              icon: const Icon(Icons.add_task),
              label: const Text('Ny registrering'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ansatt · fravær & ferie',
                  style: DriftProTheme.caption.copyWith(
                    color: DriftProTheme.primaryGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              LeavePeriodScopeButton(
                scope: _scope,
                onChanged: _onScopeChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HeroCard(
            employee: widget.employee,
            dept: dept,
            onLeaveToday: onLeaveToday,
            rate: rate,
            rateColor: rateColor,
            totalDays: stats.totalFravaerDager,
            sykmeldingDays: sykDays,
            isDark: isDark,
            hireMissing: widget.employee.hireDate == null,
            scopeLabel: _scope.shortLabel,
          ),
          const SizedBox(height: 14),
          _TypeGrid(
            stats: stats,
            year: _scope.year,
            sykmeldingDays: sykDays,
            permisjonDays: permDays,
            onFerie: () =>
                _showTypeDates(AbsenceType.ferie, 'Ferie · ${_scope.shortLabel}'),
            onEgen: () => _showTypeDates(
              AbsenceType.egenmelding,
              'Egenmelding · ${_scope.shortLabel}',
            ),
            onSykt: () => _showTypeDates(
              AbsenceType.syktBarn,
              'Sykt barn · ${_scope.shortLabel}',
            ),
            onSyk: () => _showTypeDates(
              AbsenceType.sykmelding,
              'Sykmelding · ${_scope.shortLabel}',
            ),
            onPerm: () => _showTypeDates(
              AbsenceType.permisjon,
              'Permisjon · ${_scope.shortLabel}',
            ),
          ),
          const SizedBox(height: 14),
          _EmployeeMonthChart(
            year: _scope.year,
            monthly: monthly,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          _TipsCard(tips: tips, isDark: isDark),
          const SizedBox(height: 14),
          _RulesAccordion(isDark: isDark),
          const SizedBox(height: 20),
          Text(
            'Registreringer · ${_scope.shortLabel}',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (scoped.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ingen ferie eller fravær i ${_scope.shortLabel.toLowerCase()}.',
                style: DriftProTheme.caption,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...scoped.map((a) {
              final days = a.type == AbsenceType.ferie
                  ? (a.vacationDayCount ??
                      AbsenceService.vacationDayCount(a.startDate, a.endDate))
                  : (a.totalDays ??
                      AbsenceService.dayCount(a.startDate, a.endDate));
              final approver = a.approvedBy == null
                  ? null
                  : widget.approverNames[a.approvedBy!];
              final typeColor = switch (a.type) {
                AbsenceType.ferie => DriftProTheme.absenceVacation,
                AbsenceType.egenmelding => DriftProTheme.absenceSickSelf,
                AbsenceType.syktBarn => DriftProTheme.absenceSickChild,
                AbsenceType.sykmelding => DriftProTheme.absenceSickNote,
                AbsenceType.permisjon => DriftProTheme.absenceLeave,
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isDark ? DriftProTheme.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: widget.onAbsenceTap == null
                        ? null
                        : () => widget.onAbsenceTap!(a),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? DriftProTheme.dividerDark
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 40,
                            decoration: BoxDecoration(
                              color: typeColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.type.label,
                                  style: DriftProTheme.labelMd.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${df.format(a.startDate)} – ${df.format(a.endDate)}',
                                  style: DriftProTheme.bodySm,
                                ),
                                if (approver != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Godkjent av $approver',
                                    style: DriftProTheme.caption,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$days d',
                                style: DriftProTheme.labelMd.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(a.status.label, style: DriftProTheme.caption),
                            ],
                          ),
                          if (widget.onAbsenceTap != null) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.employee,
    required this.dept,
    required this.onLeaveToday,
    required this.rate,
    required this.rateColor,
    required this.totalDays,
    required this.sykmeldingDays,
    required this.isDark,
    required this.hireMissing,
    required this.scopeLabel,
  });

  final UserProfile employee;
  final String? dept;
  final bool onLeaveToday;
  final double rate;
  final Color rateColor;
  final int totalDays;
  final int sykmeldingDays;
  final bool isDark;
  final bool hireMissing;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                child: Text(
                  employee.fullName.isNotEmpty
                      ? employee.fullName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: DriftProTheme.primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: DriftProTheme.labelLg
                          .copyWith(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      [
                        if (dept != null) dept,
                        if (employee.employeeNumber != null)
                          'nr ${employee.employeeNumber}',
                        employee.displayTitle,
                      ].where((s) => s.toString().trim().isNotEmpty).join(' · '),
                      style: DriftProTheme.caption,
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    '${rate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: rateColor,
                      height: 1,
                    ),
                  ),
                  Text(
                    'fravær',
                    style: DriftProTheme.caption.copyWith(
                      color: rateColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                onLeaveToday ? 'Borte i dag' : 'På jobb',
                onLeaveToday
                    ? DriftProTheme.warning
                    : DriftProTheme.primaryGreen,
              ),
              _chip(
                '$totalDays d fravær',
                rateColor,
              ),
              if (sykmeldingDays > 0)
                _chip(
                  '$sykmeldingDays d sykmelding',
                  DriftProTheme.absenceSickNote,
                ),
              _chip(scopeLabel, DriftProTheme.primaryGreen),
            ],
          ),
          if (hireMissing) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DriftProTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Ansettelsesdato mangler — egenmelding/sykt barn følger kalenderår.',
                style: DriftProTheme.caption.copyWith(
                  color: const Color(0xFF9A3412),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({
    required this.stats,
    required this.year,
    required this.sykmeldingDays,
    required this.permisjonDays,
    required this.onFerie,
    required this.onEgen,
    required this.onSykt,
    required this.onSyk,
    required this.onPerm,
  });

  final EmployeeLeaveSnapshot stats;
  final int year;
  final int sykmeldingDays;
  final int permisjonDays;
  final VoidCallback onFerie;
  final VoidCallback onEgen;
  final VoidCallback onSykt;
  final VoidCallback onSyk;
  final VoidCallback onPerm;

  @override
  Widget build(BuildContext context) {
    final cards = [
      LeaveEmployeeKpiCard(
        icon: Icons.beach_access,
        label: 'Ferie $year',
        value: '${stats.ferieRemaining} d',
        unit: 'igjen · ${stats.ferieUsed}/${stats.ferieTotal} brukt',
        sub: stats.ferieLevel == LeaveUsageLevel.critical
            ? 'Oppbrukt'
            : stats.ferieLevel == LeaveUsageLevel.warning
                ? 'Nær brukt opp'
                : 'Kalenderår $year',
        baseColor: DriftProTheme.absenceVacation,
        level: stats.ferieLevel,
        progress: stats.ferieProgress,
        showInfo: true,
        onInfoTap: onFerie,
      ),
      LeaveEmployeeKpiCard(
        icon: Icons.sick_outlined,
        label: 'Egenmelding',
        value: '${stats.egenDaysTotal} d',
        unit:
            '${stats.egenTilfeller}/${stats.egenTilfellerMax} tilf. · maks ${stats.egenMax} d',
        sub: stats.egenLevel == LeaveUsageLevel.critical
            ? 'Oppbrukt — krever sykmelding'
            : stats.egenLevel == LeaveUsageLevel.warning
                ? 'Nær taket'
                : stats.periodUsage.window.formatRangeWithBasis(),
        baseColor: DriftProTheme.absenceSickSelf,
        level: stats.egenLevel,
        progress: stats.egenProgress,
        showInfo: true,
        onInfoTap: onEgen,
      ),
      LeaveEmployeeKpiCard(
        icon: Icons.child_care_outlined,
        label: 'Sykt barn',
        value: '${stats.syktDays} d',
        unit: 'av ${stats.syktMax} d i perioden',
        sub: stats.syktLevel == LeaveUsageLevel.critical
            ? 'Kvote oppbrukt'
            : stats.syktLevel == LeaveUsageLevel.warning
                ? 'Nær kvoten'
                : stats.periodUsage.window.formatRangeWithBasis(),
        baseColor: DriftProTheme.absenceSickChild,
        level: stats.syktLevel,
        progress: stats.syktProgress,
        showInfo: true,
        onInfoTap: onSykt,
      ),
      LeaveEmployeeKpiCard(
        icon: Icons.medical_services_outlined,
        label: 'Sykmelding',
        value: '$sykmeldingDays d',
        unit: 'person-virkedager i perioden',
        sub: sykmeldingDays >= 16 ? 'Langvarig — følg opp' : 'Ingen kvotetak',
        baseColor: DriftProTheme.absenceSickNote,
        level: sykmeldingDays >= 16
            ? LeaveUsageLevel.warning
            : LeaveUsageLevel.ok,
        progress: (sykmeldingDays / 60).clamp(0.0, 1.0),
        showInfo: true,
        onInfoTap: onSyk,
      ),
      LeaveEmployeeKpiCard(
        icon: Icons.timer_outlined,
        label: 'Permisjon',
        value: '$permisjonDays d',
        unit: 'uten lønn i perioden',
        sub: permisjonDays > 0 ? 'Avtalt med arbeidsgiver' : 'Ingen registrert',
        baseColor: DriftProTheme.absenceLeave,
        level: LeaveUsageLevel.ok,
        progress: (permisjonDays / 20).clamp(0.0, 1.0),
        showInfo: true,
        onInfoTap: onPerm,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900
            ? 3
            : c.maxWidth >= 560
                ? 2
                : 1;
        if (cols == 1) {
          return Column(
            children: [
              for (final card in cards) ...[
                LeaveEmployeeKpiCard(
                  icon: card.icon,
                  label: card.label,
                  value: card.value,
                  unit: card.unit,
                  sub: card.sub,
                  baseColor: card.baseColor,
                  level: card.level,
                  progress: card.progress,
                  compact: false,
                  showInfo: card.showInfo,
                  onInfoTap: card.onInfoTap,
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards)
              SizedBox(
                width: (c.maxWidth - (cols - 1) * 10) / cols,
                child: card,
              ),
          ],
        );
      },
    );
  }
}

class _EmployeeMonthChart extends StatelessWidget {
  const _EmployeeMonthChart({
    required this.year,
    required this.monthly,
    required this.isDark,
  });

  final int year;
  final List<double> monthly;
  final bool isDark;

  static const _names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  @override
  Widget build(BuildContext context) {
    final maxY = monthly.fold<double>(0, math.max);
    var peak = 0;
    for (var i = 1; i < 12; i++) {
      if (monthly[i] > monthly[peak]) peak = i;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fravær per måned $year',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            maxY <= 0
                ? 'Ingen fravær registrert'
                : 'Mest i ${_names[peak]} (${monthly[peak].round()} d)',
            style: DriftProTheme.caption.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: maxY <= 0
                ? Center(child: Text('Ingen data', style: DriftProTheme.caption))
                : BarChart(
                    BarChartData(
                      maxY: (maxY * 1.3).clamp(3, double.infinity),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: isDark
                              ? Colors.white12
                              : const Color(0xFFE2E8F0),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, m) {
                              final i = v.toInt();
                              if (i < 0 || i > 11) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                _names[i],
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: i == peak
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: i == peak
                                      ? DriftProTheme.error
                                      : const Color(0xFF94A3B8),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < 12; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: monthly[i],
                                width: 12,
                                borderRadius: BorderRadius.circular(4),
                                color: i == peak
                                    ? DriftProTheme.error
                                    : DriftProTheme.primaryGreen,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.tips, required this.isDark});
  final List<String> tips;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.2 : 0.1),
            DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.06 : 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: DriftProTheme.primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                'Smarte tips',
                style:
                    DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900)),
                  Expanded(
                    child: Text(
                      tip,
                      style: DriftProTheme.bodySm.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesAccordion extends StatelessWidget {
  const _RulesAccordion({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cards = LeaveRules.managerOverviewCards().take(5).toList();
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: const Icon(Icons.gavel_rounded,
              color: DriftProTheme.primaryGreen),
          title: Text(
            'Regler & rettigheter',
            style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Egenmelding, sykt barn, ferie, sykmelding',
            style: DriftProTheme.caption,
          ),
          children: [
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        style: DriftProTheme.labelMd
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.body,
                        style: DriftProTheme.caption.copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
