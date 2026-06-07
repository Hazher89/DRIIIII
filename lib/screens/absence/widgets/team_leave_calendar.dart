import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/vacation_year_window.dart';
import '../../../core/services/absence/absence_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/business_days.dart';
import '../../../core/utils/norwegian_holidays.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

enum LeaveCalendarScale { week, month, year }

/// Kompakt teamkalender med uke / måned / år og tydelig fraværsmarkering.
class TeamLeaveCalendar extends StatefulWidget {
  final DateTime month;
  final List<Absence> absences;
  final List<UserProfile> employees;
  final String? filterUserId;
  final ValueChanged<DateTime> onMonthChanged;
  final void Function(DateTime date, List<Absence> dayAbsences)? onDayTap;
  final Color Function(AbsenceType) colorForType;
  final Set<AbsenceType>? typesFilter;
  final bool includePending;

  const TeamLeaveCalendar({
    super.key,
    required this.month,
    required this.absences,
    required this.employees,
    required this.onMonthChanged,
    required this.colorForType,
    this.filterUserId,
    this.onDayTap,
    this.typesFilter,
    this.includePending = false,
  });

  @override
  State<TeamLeaveCalendar> createState() => _TeamLeaveCalendarState();
}

class _TeamLeaveCalendarState extends State<TeamLeaveCalendar> {
  static const _weekdays = ['Ma', 'Ti', 'On', 'To', 'Fr', 'Lø', 'Sø'];
  static const double _monthCellH = 78;

  late LeaveCalendarScale _scale;
  late DateTime _focus;

  @override
  void initState() {
    super.initState();
    _scale = LeaveCalendarScale.month;
    _focus = DateTime(widget.month.year, widget.month.month, 1);
  }

  @override
  void didUpdateWidget(covariant TeamLeaveCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _focus = DateTime(widget.month.year, widget.month.month, 1);
    }
  }

  List<Absence> get _filtered {
    var base = widget.absences.where((a) {
      if (a.status == AbsenceStatus.avvist) return false;
      if (a.status == AbsenceStatus.godkjent) return true;
      return widget.includePending && a.status == AbsenceStatus.ventende;
    });
    if (widget.typesFilter != null) {
      base = base.where((a) => widget.typesFilter!.contains(a.type));
    }
    if (widget.filterUserId != null) {
      base = base.where((a) => a.userId == widget.filterUserId);
    }
    return base.toList();
  }

  void _notifyParent() {
    widget.onMonthChanged(DateTime(_focus.year, _focus.month, 1));
  }

  void _goToday() {
    setState(() => _focus = DateTime.now());
    _notifyParent();
  }

  void _shift(int delta) {
    setState(() {
      switch (_scale) {
        case LeaveCalendarScale.week:
          _focus = _focus.add(Duration(days: 7 * delta));
          break;
        case LeaveCalendarScale.month:
          _focus = DateTime(_focus.year, _focus.month + delta, 1);
          break;
        case LeaveCalendarScale.year:
          _focus = DateTime(_focus.year + delta, 1, 1);
          break;
      }
    });
    _notifyParent();
  }

  DateTime get _weekStart {
    final d = DateTime(_focus.year, _focus.month, _focus.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String get _periodTitle {
    switch (_scale) {
      case LeaveCalendarScale.week:
        final end = _weekStart.add(const Duration(days: 6));
        final fmt = DateFormat('d. MMM', 'nb_NO');
        return '${fmt.format(_weekStart)} – ${fmt.format(end)} ${_focus.year}';
      case LeaveCalendarScale.month:
        return DateFormat('MMMM yyyy', 'nb_NO').format(_focus);
      case LeaveCalendarScale.year:
        return '${_focus.year}';
    }
  }

  int _monthRowCount(DateTime m) {
    final first = DateTime(m.year, m.month, 1);
    final days = DateUtils.getDaysInMonth(m.year, m.month);
    final pad = first.weekday - 1;
    return ((pad + days) / 7).ceil();
  }

  List<Absence> _onDate(DateTime date) =>
      AbsenceService.filterActiveOnDate(_filtered, date);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(isDark),
              const SizedBox(height: 10),
              _buildWeekdayHeader(isDark),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey('$_scale-${_focus.year}-${_focus.month}-${_focus.day}'),
                  child: switch (_scale) {
                    LeaveCalendarScale.week => _buildWeekView(isDark),
                    LeaveCalendarScale.month => _buildMonthView(isDark),
                    LeaveCalendarScale.year => _buildYearView(isDark),
                  },
                ),
              ),
              const SizedBox(height: 8),
              _MonthStats(
                focus: _focus,
                absences: _filtered,
                scale: _scale,
              ),
              const SizedBox(height: 4),
              _Legend(
                colorForType: widget.colorForType,
                typesFilter: widget.typesFilter,
              ),
            ],
          ),
          ),
      ),
    );
  }

  Widget _buildToolbar(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LeaveCalendarScale>(
          segments: const [
            ButtonSegment(
              value: LeaveCalendarScale.week,
              label: Text('Uke'),
              icon: Icon(Icons.view_week_outlined, size: 16),
            ),
            ButtonSegment(
              value: LeaveCalendarScale.month,
              label: Text('Mnd'),
              icon: Icon(Icons.calendar_view_month_outlined, size: 16),
            ),
            ButtonSegment(
              value: LeaveCalendarScale.year,
              label: Text('År'),
              icon: Icon(Icons.calendar_view_month, size: 16),
            ),
          ],
          selected: {_scale},
          onSelectionChanged: (s) {
            setState(() => _scale = s.first);
            _notifyParent();
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(
              DriftProTheme.labelSm.copyWith(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shift(-1),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _periodTitle,
                    textAlign: TextAlign.center,
                    style: DriftProTheme.labelLg.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (_scale != LeaveCalendarScale.year)
                        _miniDropdown<int>(
                          value: _focus.month,
                          items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text(
                                DateFormat.MMM('nb_NO')
                                    .format(DateTime(2000, i + 1, 1)),
                              ),
                            ),
                          ),
                          onChanged: (m) {
                            if (m == null) return;
                            setState(() {
                              _focus = DateTime(_focus.year, m, 1);
                            });
                            _notifyParent();
                          },
                        ),
                      _miniDropdown<int>(
                        value: _focus.year,
                        items: VacationYearWindow.years
                            .map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text('$y'),
                              ),
                            )
                            .toList(),
                        onChanged: (y) {
                          if (y == null) return;
                          setState(() {
                            _focus = DateTime(
                              y,
                              _scale == LeaveCalendarScale.year ? 1 : _focus.month,
                              1,
                            );
                          });
                          _notifyParent();
                        },
                      ),
                      TextButton.icon(
                        onPressed: _goToday,
                        icon: const Icon(Icons.today_outlined, size: 16),
                        label: const Text('I dag'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shift(1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildWeekdayHeader(bool isDark) {
    return Row(
      children: _weekdays
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMonthView(bool isDark) {
    final rows = _monthRowCount(_focus);
    final firstDay = DateTime(_focus.year, _focus.month, 1);
    final pad = firstDay.weekday - 1;
    final daysInMonth = DateUtils.getDaysInMonth(_focus.year, _focus.month);

    return SizedBox(
      height: rows * _monthCellH,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: _monthCellH,
        ),
        itemCount: rows * 7,
        itemBuilder: (context, index) {
          final dayIndex = index - pad + 1;
          if (dayIndex < 1 || dayIndex > daysInMonth) {
            return const SizedBox.shrink();
          }
          final date = DateTime(_focus.year, _focus.month, dayIndex);
          return _dayCell(date, dayIndex, isDark, compact: true);
        },
      ),
    );
  }

  Widget _buildWeekView(bool isDark) {
    final start = _weekStart;
    return SizedBox(
      height: 96,
      child: Row(
        children: List.generate(7, (i) {
          final date = start.add(Duration(days: i));
          return Expanded(
            child: _dayCell(date, date.day, isDark, compact: false),
          );
        }),
      ),
    );
  }

  Widget _buildYearView(bool isDark) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemCount: 12,
      itemBuilder: (context, i) {
        final m = DateTime(_focus.year, i + 1, 1);
        final daysWithLeave = <int>{};
        for (var d = 1; d <= DateUtils.getDaysInMonth(m.year, m.month); d++) {
          final date = DateTime(m.year, m.month, d);
          if (_onDate(date).isNotEmpty) daysWithLeave.add(d);
        }
        final ferieDays = <int>{};
        for (var d = 1; d <= DateUtils.getDaysInMonth(m.year, m.month); d++) {
          final date = DateTime(m.year, m.month, d);
          if (_onDate(date).any((a) => a.type == AbsenceType.ferie)) {
            ferieDays.add(d);
          }
        }

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _scale = LeaveCalendarScale.month;
              _focus = m;
            });
            _notifyParent();
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.MMM('nb_NO').format(m),
                  style: DriftProTheme.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: daysWithLeave.take(20).map((d) {
                      final isFerie = ferieDays.contains(d);
                      return Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isFerie
                              ? widget.colorForType(AbsenceType.ferie)
                              : DriftProTheme.warning,
                          shape: BoxShape.circle,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (daysWithLeave.isNotEmpty)
                  Text(
                    '${daysWithLeave.length} d.',
                    style: DriftProTheme.caption.copyWith(fontSize: 9),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dayCell(DateTime date, int dayNum, bool isDark, {required bool compact}) {
    final dayAbsences = _onDate(date);
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final isWeekend = date.weekday >= 6;
    final isRedDay = NorwegianHolidays.isRedDay(date);
    final holidayName = BusinessDays.holidayName(date);
    final hasFerie = dayAbsences.any((a) => a.type == AbsenceType.ferie);
    final primaryColor = dayAbsences.isEmpty
        ? null
        : (hasFerie
            ? widget.colorForType(AbsenceType.ferie)
            : widget.colorForType(dayAbsences.first.type));

    Color? bg;
    if (primaryColor != null) {
      bg = primaryColor.withValues(alpha: isDark ? 0.28 : 0.18);
    } else if (isRedDay) {
      bg = Colors.red.withValues(alpha: isDark ? 0.22 : 0.1);
    } else if (isWeekend) {
      bg = isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.grey.shade100.withValues(alpha: 0.7);
    } else if (isToday) {
      bg = DriftProTheme.primaryGreen.withValues(alpha: 0.1);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onDayTap != null
            ? () => widget.onDayTap!(date, dayAbsences)
            : null,
        child: Tooltip(
          message: holidayName ?? (dayAbsences.isNotEmpty
              ? dayAbsences.map((a) => '${a.userName ?? "?"}: ${a.type.label}').join('\n')
              : ''),
          child: Container(
          margin: const EdgeInsets.all(1.5),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 4,
            vertical: compact ? 2 : 6,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? DriftProTheme.primaryGreen
                  : (isRedDay
                      ? Colors.red.shade400
                      : (primaryColor != null
                          ? primaryColor.withValues(alpha: 0.5)
                          : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200))),
              width: isToday ? 1.5 : (isRedDay ? 1.2 : 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isRedDay)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: Colors.red.shade700,
                      ),
                    ),
                  Text(
                    '$dayNum',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      color: isRedDay
                          ? Colors.red.shade800
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              ),
              if (isRedDay && compact && holidayName != null)
                Text(
                  holidayName.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade700,
                  ),
                ),
              if (dayAbsences.isNotEmpty) ...[
                const SizedBox(height: 2),
                if (compact)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: dayAbsences.take(3).map((a) {
                      return Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: widget.colorForType(a.type),
                          shape: BoxShape.circle,
                        ),
                      );
                    }).toList(),
                  )
                else
                  ...dayAbsences.take(3).map(
                        (a) => Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.colorForType(a.type),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${a.type.label} · ${(a.userName ?? '?').split(' ').first}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                if (dayAbsences.length > 3)
                  Text(
                    '+${dayAbsences.length - 3}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _MonthStats extends StatelessWidget {
  final DateTime focus;
  final List<Absence> absences;
  final LeaveCalendarScale scale;

  const _MonthStats({
    required this.focus,
    required this.absences,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    if (scale != LeaveCalendarScale.month) return const SizedBox.shrink();

    final redCount = NorwegianHolidays.forMonth(focus.year, focus.month).length;
    final people = absences.map((a) => a.userId).toSet().length;
    final pending = absences.where((a) => a.status == AbsenceStatus.ventende).length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _stat(Icons.people_outline, '$people ansatte', DriftProTheme.primaryGreen),
          _stat(Icons.hourglass_top, '$pending venter', DriftProTheme.warning),
          _stat(Icons.event_busy, '$redCount røde dager', Colors.red.shade700),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color Function(AbsenceType) colorForType;
  final Set<AbsenceType>? typesFilter;

  const _Legend({required this.colorForType, this.typesFilter});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final types = typesFilter ?? AbsenceType.values.toSet();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          ...types.map((t) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorForType(t),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(t.label, style: const TextStyle(fontSize: 10)),
              ],
            );
          }),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Rød dag', style: TextStyle(fontSize: 10)),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange.shade700),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Venter', style: TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
