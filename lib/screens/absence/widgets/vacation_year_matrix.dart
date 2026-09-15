import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/vacation_export_service.dart';
import '../../../core/services/absence/vacation_year_matrix_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/norwegian_holidays.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import 'leave_public_holidays_panel.dart';

/// Årsmatrise: ansatte × uker/måneder — smart ferieoversikt.
class VacationYearMatrix extends StatefulWidget {
  const VacationYearMatrix({
    super.key,
    required this.year,
    required this.employees,
    required this.vacations,
    this.companyName,
    this.onYearChanged,
  });

  final int year;
  final List<UserProfile> employees;
  final List<Absence> vacations;
  final String? companyName;
  final ValueChanged<int>? onYearChanged;

  @override
  State<VacationYearMatrix> createState() => _VacationYearMatrixState();
}

class _VacationYearMatrixState extends State<VacationYearMatrix> {
  static const _nameW = 132.0;
  static const _cellW = 28.0;
  static const _cellH = 34.0;

  bool _exporting = false;
  late VacationYearMatrixModel _model;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant VacationYearMatrix oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        oldWidget.employees != widget.employees ||
        oldWidget.vacations != widget.vacations) {
      _rebuild();
    }
  }

  void _rebuild() {
    _model = VacationYearMatrixModel.build(
      year: widget.year,
      employees: widget.employees,
      vacations: widget.vacations,
    );
  }

  Future<void> _export(bool pdf) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      if (pdf) {
        await VacationExportService.exportPdf(
          year: widget.year,
          employees: widget.employees,
          vacations: widget.vacations,
          companyName: widget.companyName,
        );
      } else {
        await VacationExportService.exportExcel(
          year: widget.year,
          employees: widget.employees,
          vacations: widget.vacations,
          companyName: widget.companyName,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pdf ? 'PDF eksportert' : 'Excel eksportert')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eksport feilet: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final holidays = NorwegianHolidays.forYear(widget.year);
    final holidayWeeks = <int>{
      for (final h in holidays) VacationYearMatrixModel.isoWeekNumber(h.date),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(isDark),
        const SizedBox(height: 10),
        _tips(isDark),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _monthHeader(isDark),
                    _weekHeader(isDark, holidayWeeks),
                    ..._model.employeeRows.map((r) => _employeeRow(r, isDark, holidayWeeks)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    _legendDot(DriftProTheme.primaryGreen, 'Godkjent'),
                    const SizedBox(width: 12),
                    _legendDot(Colors.orange.shade700, 'Ventende'),
                    const SizedBox(width: 12),
                    _legendDot(Colors.red.shade300, 'Rød uke'),
                    const Spacer(),
                    Text(
                      'Hold over celle for dager',
                      style: DriftProTheme.caption.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LeavePublicHolidaysPanel(year: widget.year, initiallyExpanded: true),
      ],
    );
  }

  Widget _header(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: 0.12),
            isDark ? DriftProTheme.cardDark : const Color(0xFFF8FBF8),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Forrige år',
            onPressed: widget.onYearChanged == null
                ? null
                : () => widget.onYearChanged!(widget.year - 1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Ferie ${widget.year}',
                  style: DriftProTheme.headingSm.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_model.employeeRows.length} ansatte · '
                  '${_model.employeeRows.where((e) => e.totalWorkDays > 0).length} med ferie',
                  style: DriftProTheme.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Neste år',
            onPressed: widget.onYearChanged == null
                ? null
                : () => widget.onYearChanged!(widget.year + 1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Eksporter',
            enabled: !_exporting,
            onSelected: (v) => _export(v == 'pdf'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'xlsx', child: Text('Eksporter Excel')),
              PopupMenuItem(value: 'pdf', child: Text('Eksporter PDF')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _exporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.ios_share_rounded, color: DriftProTheme.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tips(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tips for ${widget.year}',
                  style: DriftProTheme.labelLg.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Hovedferie (18 dager) bør tas 1. juni–30. september.\n'
                  '• Tall i cellen = virkedager i den uken (ikke helg/røde dager).\n'
                  '• Sammenhengende ferie over flere uker vises som én periode ved hover.\n'
                  '• ${LeaveRules.ferieLegalMinimumDays} feriedager er lovens minimum.',
                  style: DriftProTheme.bodySm.copyWith(
                    height: 1.35,
                    color: Colors.brown.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthHeader(bool isDark) {
    return Row(
      children: [
        SizedBox(
          width: _nameW,
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                'Ansatt',
                style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        ..._model.monthSpans.map((m) {
          return Container(
            width: _cellW * m.weekCount,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.06),
            ),
            child: Text(
              m.label,
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          );
        }),
        SizedBox(
          width: 44,
          height: 28,
          child: Center(
            child: Text(
              'Σ',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _weekHeader(bool isDark, Set<int> holidayWeeks) {
    return Row(
      children: [
        SizedBox(width: _nameW, height: 26),
        ..._model.weeks.map((w) {
          final red = holidayWeeks.contains(w.week);
          return Container(
            width: _cellW,
            height: 26,
            alignment: Alignment.center,
            color: red ? Colors.red.withValues(alpha: 0.08) : null,
            child: Text(
              '${w.week}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: red ? Colors.red.shade700 : Colors.grey.shade600,
              ),
            ),
          );
        }),
        const SizedBox(width: 44),
      ],
    );
  }

  Widget _employeeRow(
    VacationEmployeeRow row,
    bool isDark,
    Set<int> holidayWeeks,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _nameW,
            height: _cellH,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          ..._model.weeks.map((w) {
            final days = row.daysInWeek[w.week] ?? 0;
            final span = _model.spanForWeek(row, w.week);
            final red = holidayWeeks.contains(w.week);
            final pending = span?.status == AbsenceStatus.ventende;
            final color = days == 0
                ? Colors.transparent
                : (pending
                    ? Colors.orange.shade600
                    : DriftProTheme.primaryGreen);
            final tip = span == null
                ? (days > 0 ? '${row.name}: $days dager i uke ${w.week}' : null)
                : span.tooltip(row.name);

            return Tooltip(
              message: tip ?? '',
              waitDuration: const Duration(milliseconds: 250),
              child: Container(
                width: _cellW,
                height: _cellH,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: red ? Colors.red.withValues(alpha: 0.04) : null,
                  border: Border(
                    left: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
                  ),
                ),
                child: days > 0
                    ? Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$days',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : null,
              ),
            );
          }),
          SizedBox(
            width: 44,
            height: _cellH,
            child: Center(
              child: Text(
                row.totalWorkDays > 0 ? '${row.totalWorkDays}' : '—',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: row.totalWorkDays > 0
                      ? DriftProTheme.primaryGreen
                      : Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label, style: DriftProTheme.caption),
      ],
    );
  }
}
