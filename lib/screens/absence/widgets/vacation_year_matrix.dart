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
    final mq = MediaQuery.sizeOf(context).width;
    final width = (maxWidth.isFinite && maxWidth >= 200)
        ? maxWidth
        : (mq - 40).clamp(320.0, 2400.0);
    final nameW = width >= 1200
        ? 168.0
        : width >= 900
            ? 148.0
            : width >= 600
                ? 128.0
                : 104.0;
    final sumW = width >= 900 ? 52.0 : 44.0;
    final weeksN = _model.weeks.length.clamp(1, 60);
    final weeksAvail = (width - nameW - sumW).clamp(120.0, 4000.0);
    const minCell = 24.0;
    final fillCell = weeksAvail / weeksN;
    final needsScroll = fillCell < minCell;
    final cellW = needsScroll ? minCell : fillCell;
    final monthH = width >= 900 ? 32.0 : 28.0;
    final weekH = width >= 900 ? 28.0 : 24.0;
    final rowH = width >= 1100
        ? 42.0
        : width >= 800
            ? 38.0
            : 34.0;
    final weekFont = cellW >= 34 ? 11.5 : cellW >= 28 ? 10.0 : 9.0;
    final dayFont = cellW >= 34 ? 12.5 : cellW >= 28 ? 11.0 : 10.0;
    final nameFont = nameW >= 140 ? 13.0 : 12.0;
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
      setState(_rebuild);
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

    // Tydelige linjer — ikke nesten usynlige gråtoner.
    final border = isDark ? const Color(0xFF4A5560) : const Color(0xFFC5D0C8);
    final borderStrong =
        isDark ? const Color(0xFF6B7785) : const Color(0xFF9AAEA2);
    final headerBg =
        isDark ? const Color(0xFF1E2A24) : const Color(0xFFE8F2EB);
    final nameBg = isDark ? DriftProTheme.cardDark : const Color(0xFFF7FAF8);
    final zebraBg =
        isDark ? const Color(0xFF171E1A) : const Color(0xFFF0F5F2);

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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderStrong, width: 1.4),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 3,
                color: DriftProTheme.primaryGreen,
              ),
              _grid(
                isDark: isDark,
                holidayWeeks: holidayWeeks,
                border: border,
                borderStrong: borderStrong,
                headerBg: headerBg,
                nameBg: nameBg,
                zebraBg: zebraBg,
              ),
              Container(height: 1.2, color: borderStrong),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _legendDot(DriftProTheme.primaryGreen, 'Godkjent'),
                    _legendDot(Colors.orange.shade700, 'Ventende'),
                    _legendDot(Colors.red.shade400, 'Rød uke'),
                    Text(
                      'Hold over celle for periode',
                      style: DriftProTheme.caption.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey.shade700,
                        fontSize: 11.5,
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
    required Color borderStrong,
    required Color headerBg,
    required Color nameBg,
    required Color zebraBg,
  }) {
    // Uker som starter en ny måned — tykkere vertikal linje.
    final monthStarts = <int>{};
    for (var i = 0; i < _model.weeks.length; i++) {
      if (i == 0 ||
          _model.weeks[i].month != _model.weeks[i - 1].month) {
        monthStarts.add(i);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final m = _metricsFor(constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (m.needsScroll)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
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
                        borderStrong,
                        height: m.monthH + m.weekH,
                        alignCenter: false,
                        rightBorder: true,
                        strong: true,
                      ),
                      ..._model.employeeRows.asMap().entries.map(
                        (e) => _nameCell(
                          e.value.name,
                          e.key.isEven ? nameBg : zebraBg,
                          border,
                          borderStrong,
                          m,
                        ),
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
                            _monthRow(headerBg, border, borderStrong, m),
                            _weekRow(
                              holidayWeeks,
                              headerBg,
                              border,
                              borderStrong,
                              monthStarts,
                              m,
                            ),
                            ..._model.employeeRows.asMap().entries.map(
                              (e) => _weekCells(
                                e.value,
                                e.key,
                                holidayWeeks,
                                border,
                                borderStrong,
                                monthStarts,
                                e.key.isEven ? nameBg : zebraBg,
                                m,
                              ),
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
                        borderStrong,
                        height: m.monthH + m.weekH,
                        alignCenter: true,
                        rightBorder: false,
                        leftBorder: true,
                        strong: true,
                      ),
                      ..._model.employeeRows.asMap().entries.map(
                        (e) => _sumCell(
                          e.value,
                          e.key.isEven ? nameBg : zebraBg,
                          border,
                          borderStrong,
                          m,
                        ),
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
    bool strong = false,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      alignment: alignCenter ? Alignment.center : Alignment.centerLeft,
      padding: alignCenter
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: border, width: strong ? 1.5 : 1.2),
          right: rightBorder
              ? BorderSide(color: border, width: 1.5)
              : BorderSide.none,
          left: leftBorder
              ? BorderSide(color: border, width: 1.5)
              : BorderSide.none,
        ),
      ),
      child: Text(
        label,
        style: DriftProTheme.caption.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _nameCell(
    String name,
    Color bg,
    Color border,
    Color borderStrong,
    _MatrixMetrics m,
  ) {
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 280),
      child: Container(
        width: double.infinity,
        height: m.rowH,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(color: border, width: 1.1),
            right: BorderSide(color: borderStrong, width: 1.5),
          ),
        ),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: m.nameFont,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _sumCell(
    VacationEmployeeRow row,
    Color bg,
    Color border,
    Color borderStrong,
    _MatrixMetrics m,
  ) {
    return Container(
      width: double.infinity,
      height: m.rowH,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: border, width: 1.1),
          left: BorderSide(color: borderStrong, width: 1.5),
        ),
      ),
      child: Text(
        row.totalWorkDays > 0 ? '${row.totalWorkDays}' : '—',
        style: TextStyle(
          fontSize: m.nameFont,
          fontWeight: FontWeight.w900,
          color: row.totalWorkDays > 0
              ? DriftProTheme.primaryGreen
              : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _monthRow(
    Color headerBg,
    Color border,
    Color borderStrong,
    _MatrixMetrics m,
  ) {
    return SizedBox(
      height: m.monthH,
      child: Row(
        children: _model.monthSpans.asMap().entries.map((e) {
          final month = e.value;
          return Container(
            width: m.cellW * month.weekCount,
            height: m.monthH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(color: borderStrong, width: 1.4),
                left: BorderSide(
                  color: e.key == 0 ? borderStrong : borderStrong,
                  width: e.key == 0 ? 0 : 1.6,
                ),
              ),
            ),
            child: Text(
              month.label,
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: m.cellW >= 28 ? 12.5 : 11,
                color: DriftProTheme.primaryGreenDark,
                letterSpacing: 0.3,
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
    Color borderStrong,
    Set<int> monthStarts,
    _MatrixMetrics m,
  ) {
    return SizedBox(
      height: m.weekH,
      child: Row(
        children: _model.weeks.asMap().entries.map((e) {
          final w = e.value;
          final red = holidayWeeks.contains(w.week);
          final monthEdge = monthStarts.contains(e.key) && e.key > 0;
          return Container(
            width: m.cellW,
            height: m.weekH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: red
                  ? const Color(0xFFFFE8E8)
                  : headerBg.withValues(alpha: 0.85),
              border: Border(
                bottom: BorderSide(color: borderStrong, width: 1.3),
                left: BorderSide(
                  color: monthEdge ? borderStrong : border,
                  width: monthEdge ? 1.6 : 1.0,
                ),
              ),
            ),
            child: Text(
              '${w.week}',
              style: TextStyle(
                fontSize: m.weekFont,
                fontWeight: FontWeight.w800,
                color: red ? Colors.red.shade800 : const Color(0xFF4A5C52),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _weekCells(
    VacationEmployeeRow row,
    int rowIndex,
    Set<int> holidayWeeks,
    Color border,
    Color borderStrong,
    Set<int> monthStarts,
    Color rowBg,
    _MatrixMetrics m,
  ) {
    return SizedBox(
      height: m.rowH,
      child: Row(
        children: _model.weeks.asMap().entries.map((e) {
          final w = e.value;
          final days = row.daysInWeek[w.week] ?? 0;
          final span = _model.spanForWeek(row, w.week);
          final red = holidayWeeks.contains(w.week);
          final monthEdge = monthStarts.contains(e.key) && e.key > 0;
          final pending = span?.status == AbsenceStatus.ventende;
          final color = days == 0
              ? Colors.transparent
              : (pending
                  ? const Color(0xFFE67E22)
                  : DriftProTheme.primaryGreen);
          final tip = span == null
              ? (days > 0 ? '${row.name}: $days dager i uke ${w.week}' : '')
              : span.tooltip(row.name);

          final padX = (m.cellW * 0.1).clamp(2.0, 5.0);
          final padY = (m.rowH * 0.16).clamp(4.0, 9.0);

          final cell = Container(
            width: m.cellW,
            height: m.rowH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: red
                  ? Color.alphaBlend(
                      const Color(0xFFFFE0E0).withValues(alpha: 0.55),
                      rowBg,
                    )
                  : rowBg,
              border: Border(
                bottom: BorderSide(color: border, width: 1.1),
                left: BorderSide(
                  color: monthEdge ? borderStrong : border,
                  width: monthEdge ? 1.6 : 1.0,
                ),
              ),
            ),
            child: days > 0
                ? Container(
                    width: m.cellW - padX * 2,
                    height: m.rowH - padY * 2,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.28),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$days',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: m.dayFont,
                        fontWeight: FontWeight.w900,
                        height: 1,
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
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: c.withValues(alpha: 0.25),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: DriftProTheme.caption.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
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
