import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/vacation_export_service.dart';
import '../../../core/services/absence/vacation_year_matrix_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/norwegian_holidays.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import 'leave_public_holidays_panel.dart';

/// Årsmatrise: ansatte × uker/måneder — sticky navn/sum, scroller med siden.
class VacationYearMatrix extends StatefulWidget {
  const VacationYearMatrix({
    super.key,
    required this.year,
    required this.employees,
    required this.vacations,
    this.companyName,
    this.onYearChanged,
    this.onAbsenceTap,
    this.canManage = false,
  });

  final int year;
  final List<UserProfile> employees;
  final List<Absence> vacations;
  final String? companyName;
  final ValueChanged<int>? onYearChanged;
  final void Function(Absence absence)? onAbsenceTap;
  final bool canManage;

  @override
  State<VacationYearMatrix> createState() => _VacationYearMatrixState();
}

class _VacationYearMatrixState extends State<VacationYearMatrix> {
  bool _exporting = false;
  bool _tipsOpen = false;
  late VacationYearMatrixModel _model;
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  /// Skalerer matrisen etter tilgjengelig bredde — fyller laptop, scroller på smalt.
  _MatrixMetrics _metricsFor(double maxWidth) {
    final width = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 720.0;
    final nameW = width >= 1200
        ? 160.0
        : width >= 900
            ? 136.0
            : width >= 600
                ? 118.0
                : 96.0;
    final sumW = width >= 900 ? 48.0 : 40.0;
    final weeksN = _model.weeks.length.clamp(1, 60);
    final weeksAvail = (width - nameW - sumW).clamp(120.0, 4000.0);
    const minCell = 22.0;
    final fillCell = weeksAvail / weeksN;
    final needsScroll = fillCell < minCell;
    final cellW = needsScroll ? minCell : fillCell;
    final monthH = width >= 900 ? 30.0 : 26.0;
    final weekH = width >= 900 ? 26.0 : 22.0;
    final rowH = width >= 1100
        ? 40.0
        : width >= 800
            ? 36.0
            : 32.0;
    final weekFont = cellW >= 34 ? 11.0 : cellW >= 28 ? 9.5 : 8.5;
    final dayFont = cellW >= 34 ? 12.0 : cellW >= 28 ? 10.5 : 9.5;
    final nameFont = nameW >= 130 ? 13.0 : 11.5;
    return _MatrixMetrics(
      nameW: nameW,
      sumW: sumW,
      cellW: cellW,
      weeksW: cellW * weeksN,
      monthH: monthH,
      weekH: weekH,
      rowH: rowH,
      weekFont: weekFont,
      dayFont: dayFont,
      nameFont: nameFont,
      needsScroll: needsScroll,
    );
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

  void _openSpan(VacationEmployeeRow row, VacationSpan span) {
    final ids = span.absenceIds.toSet();
    final list = widget.vacations.where((a) => ids.contains(a.id)).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (list.isEmpty) return;

    if (list.length == 1 && widget.onAbsenceTap != null) {
      widget.onAbsenceTap!(list.first);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(row.name, style: DriftProTheme.headingSm),
                const SizedBox(height: 2),
                Text(
                  '${span.periodLabel} · ${span.daysLabel} · ${span.statusLabel}',
                  style: DriftProTheme.caption,
                ),
                const SizedBox(height: 12),
                ...list.map((a) {
                  final pending = a.status == AbsenceStatus.ventende;
                  final color = pending
                      ? Colors.orange.shade700
                      : DriftProTheme.primaryGreen;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(
                        pending ? Icons.hourglass_top_rounded : Icons.check,
                        color: color,
                        size: 18,
                      ),
                    ),
                    title: Text(a.type.label),
                    subtitle: Text(
                      '${a.startDate.day}.${a.startDate.month.toString().padLeft(2, '0')} – '
                      '${a.endDate.day}.${a.endDate.month.toString().padLeft(2, '0')}.${a.endDate.year}'
                      ' · ${a.status.label}',
                    ),
                    trailing: widget.canManage && pending
                        ? Text(
                            'Behandle',
                            style: TextStyle(
                              color: DriftProTheme.primaryGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onAbsenceTap?.call(a);
                    },
                  );
                }),
                if (isDark) const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final holidays = NorwegianHolidays.forYear(widget.year);
    final holidayWeeks = <int>{
      for (final h in holidays) VacationYearMatrixModel.isoWeekNumber(h.date),
    };
    final withVacation =
        _model.employeeRows.where((e) => e.totalWorkDays > 0).length;
    final border = isDark ? DriftProTheme.dividerDark : const Color(0xFFE6EBE8);
    final headerBg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF3F7F4);
    final nameBg = isDark ? DriftProTheme.cardDark : const Color(0xFFFAFCFA);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(isDark, withVacation),
        const SizedBox(height: 8),
        _tipsChip(isDark),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grid(
                isDark: isDark,
                holidayWeeks: holidayWeeks,
                border: border,
                headerBg: headerBg,
                nameBg: nameBg,
              ),
              Divider(height: 1, color: border),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _legendDot(DriftProTheme.primaryGreen, 'Godkjent'),
                    _legendDot(Colors.orange.shade700, 'Ventende'),
                    _legendDot(Colors.red.shade300, 'Rød uke'),
                    Text(
                      'Hold over celle for periode',
                      style: DriftProTheme.caption.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LeavePublicHolidaysPanel(year: widget.year, initiallyExpanded: false),
      ],
    );
  }

  Widget _toolbar(bool isDark, int withVacation) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
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
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                '${_model.employeeRows.length} ansatte · $withVacation med ferie',
                style: DriftProTheme.caption.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
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
            padding: const EdgeInsets.only(left: 4, right: 2),
            child: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.ios_share_rounded,
                    size: 22,
                    color: DriftProTheme.primaryGreen,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _tipsChip(bool isDark) {
    return Material(
      color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFFFF8E7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _tipsOpen = !_tipsOpen),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tips for ${widget.year}',
                      style: DriftProTheme.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                  Icon(
                    _tipsOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: Colors.amber.shade900,
                  ),
                ],
              ),
              if (_tipsOpen) ...[
                const SizedBox(height: 6),
                Text(
                  '• Hovedferie (18 dager) bør tas 1. juni–30. september.\n'
                  '• Tall i cellen = virkedager den uken (ikke helg/røde dager).\n'
                  '• Sammenhengende ferie over flere uker = én periode ved hover.\n'
                  '• ${LeaveRules.ferieLegalMinimumDays} feriedager er lovens minimum.',
                  style: DriftProTheme.bodySm.copyWith(
                    height: 1.35,
                    fontSize: 12,
                    color: Colors.brown.shade900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid({
    required bool isDark,
    required Set<int> holidayWeeks,
    required Color border,
    required Color headerBg,
    required Color nameBg,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = _metricsFor(constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (m.needsScroll)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(
                  '← Bla sidelengs for hele året →',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.caption.copyWith(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: m.nameW,
                  child: Column(
                    children: [
                      _cornerCell(
                        'Ansatt',
                        headerBg,
                        border,
                        height: m.monthH + m.weekH,
                        alignCenter: false,
                        rightBorder: true,
                      ),
                      ..._model.employeeRows.map(
                        (r) => _nameCell(r.name, nameBg, border, m),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _hScroll,
                    thumbVisibility: m.needsScroll,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      child: SizedBox(
                        width: m.weeksW,
                        child: Column(
                          children: [
                            _monthRow(headerBg, border, m),
                            _weekRow(holidayWeeks, headerBg, border, m),
                            ..._model.employeeRows.map(
                              (r) =>
                                  _weekCells(r, holidayWeeks, border, isDark, m),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: m.sumW,
                  child: Column(
                    children: [
                      _cornerCell(
                        'Σ',
                        headerBg,
                        border,
                        height: m.monthH + m.weekH,
                        alignCenter: true,
                        rightBorder: false,
                        leftBorder: true,
                      ),
                      ..._model.employeeRows.map(
                        (r) => _sumCell(r, nameBg, border, m),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _cornerCell(
    String label,
    Color bg,
    Color border, {
    required double height,
    required bool alignCenter,
    bool rightBorder = false,
    bool leftBorder = false,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      alignment: alignCenter ? Alignment.center : Alignment.centerLeft,
      padding: alignCenter
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: border),
          right: rightBorder ? BorderSide(color: border) : BorderSide.none,
          left: leftBorder ? BorderSide(color: border) : BorderSide.none,
        ),
      ),
      child: Text(
        label,
        style: DriftProTheme.caption.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _nameCell(
    String name,
    Color bg,
    Color border,
    _MatrixMetrics m,
  ) {
    return Container(
      width: double.infinity,
      height: m.rowH,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: border.withValues(alpha: 0.7)),
          right: BorderSide(color: border),
        ),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: m.nameFont, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sumCell(
    VacationEmployeeRow row,
    Color bg,
    Color border,
    _MatrixMetrics m,
  ) {
    return Container(
      width: double.infinity,
      height: m.rowH,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: border.withValues(alpha: 0.7)),
          left: BorderSide(color: border),
        ),
      ),
      child: Text(
        row.totalWorkDays > 0 ? '${row.totalWorkDays}' : '—',
        style: TextStyle(
          fontSize: m.nameFont,
          fontWeight: FontWeight.w800,
          color: row.totalWorkDays > 0
              ? DriftProTheme.primaryGreen
              : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _monthRow(Color headerBg, Color border, _MatrixMetrics m) {
    return SizedBox(
      height: m.monthH,
      child: Row(
        children: _model.monthSpans.map((month) {
          return Container(
            width: m.cellW * month.weekCount,
            height: m.monthH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(color: border),
                left: BorderSide(color: border.withValues(alpha: 0.5)),
              ),
            ),
            child: Text(
              month.label,
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: m.cellW >= 30 ? 12 : 10.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _weekRow(
    Set<int> holidayWeeks,
    Color headerBg,
    Color border,
    _MatrixMetrics m,
  ) {
    return SizedBox(
      height: m.weekH,
      child: Row(
        children: _model.weeks.map((w) {
          final red = holidayWeeks.contains(w.week);
          return Container(
            width: m.cellW,
            height: m.weekH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: red
                  ? Colors.red.withValues(alpha: 0.08)
                  : headerBg.withValues(alpha: 0.65),
              border: Border(
                bottom: BorderSide(color: border),
                left: BorderSide(color: border.withValues(alpha: 0.35)),
              ),
            ),
            child: Text(
              '${w.week}',
              style: TextStyle(
                fontSize: m.weekFont,
                fontWeight: FontWeight.w700,
                color: red ? Colors.red.shade700 : Colors.grey.shade600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _weekCells(
    VacationEmployeeRow row,
    Set<int> holidayWeeks,
    Color border,
    bool isDark,
    _MatrixMetrics m,
  ) {
    return SizedBox(
      height: m.rowH,
      child: Row(
        children: _model.weeks.map((w) {
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
              ? (days > 0 ? '${row.name}: $days dager i uke ${w.week}' : '')
              : span.tooltip(row.name);

          final padX = (m.cellW * 0.08).clamp(1.5, 4.0);
          final padY = (m.rowH * 0.14).clamp(3.0, 8.0);

          final cell = Container(
            width: m.cellW,
            height: m.rowH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: red ? Colors.red.withValues(alpha: 0.035) : null,
              border: Border(
                bottom: BorderSide(color: border.withValues(alpha: 0.55)),
                left: BorderSide(color: border.withValues(alpha: 0.35)),
              ),
            ),
            child: days > 0
                ? Container(
                    width: m.cellW - padX * 2,
                    height: m.rowH - padY * 2,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$days',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: m.dayFont,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : null,
          );

          Widget wrapped = tip.isEmpty
              ? cell
              : Tooltip(
                  message: tip,
                  waitDuration: const Duration(milliseconds: 220),
                  child: cell,
                );

          if (days > 0 && span != null && widget.onAbsenceTap != null) {
            wrapped = MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openSpan(row, span),
                child: wrapped,
              ),
            );
          }
          return wrapped;
        }).toList(),
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: DriftProTheme.caption.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _MatrixMetrics {
  const _MatrixMetrics({
    required this.nameW,
    required this.sumW,
    required this.cellW,
    required this.weeksW,
    required this.monthH,
    required this.weekH,
    required this.rowH,
    required this.weekFont,
    required this.dayFont,
    required this.nameFont,
    required this.needsScroll,
  });

  final double nameW;
  final double sumW;
  final double cellW;
  final double weeksW;
  final double monthH;
  final double weekH;
  final double rowH;
  final double weekFont;
  final double dayFont;
  final double nameFont;
  final bool needsScroll;
}
