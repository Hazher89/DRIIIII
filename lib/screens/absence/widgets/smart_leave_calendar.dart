import 'package:flutter/material.dart';

import '../../../core/constants/vacation_year_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/business_days.dart';
import '../../../models/absence.dart';

/// Norsk kalender. Trykk start, deretter slutt. Alle måneder i årsvinduet er synlige.
Future<DateTimeRange?> showSmartLeaveCalendar(
  BuildContext context, {
  required AbsenceType type,
  required int maxWorkDays,
  DateTime? initialStart,
  DateTime? initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final first = firstDate ?? VacationYearWindow.earliestSelectableDate;
  final last = lastDate ?? VacationYearWindow.latestSelectableDate;
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SmartLeaveCalendar(
      type: type,
      maxWorkDays: maxWorkDays,
      initialStart: initialStart,
      initialEnd: initialEnd,
      firstDate: first,
      lastDate: last,
    ),
  );
}

class _SmartLeaveCalendar extends StatefulWidget {
  const _SmartLeaveCalendar({
    required this.type,
    required this.maxWorkDays,
    required this.firstDate,
    required this.lastDate,
    this.initialStart,
    this.initialEnd,
  });

  final AbsenceType type;
  final int maxWorkDays;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<_SmartLeaveCalendar> createState() => _SmartLeaveCalendarState();
}

class _SmartLeaveCalendarState extends State<_SmartLeaveCalendar> {
  static const _months = [
    'Januar', 'Februar', 'Mars', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Desember',
  ];
  static const _weekdays = ['Man', 'Tir', 'Ons', 'Tor', 'Fre', 'Lør', 'Søn'];

  late final List<DateTime> _monthList;
  late final List<int> _years;
  late final List<GlobalKey> _monthKeys;
  late final ScrollController _yearChipScroll;

  DateTime? _start;
  DateTime? _end;
  bool _pickingEnd = false;
  int _selectedYearChip = DateTime.now().year;
  late final DateTime _initialFocus;

  bool get _isEgen => widget.type == AbsenceType.egenmelding;

  @override
  void initState() {
    super.initState();
    final now = BusinessDays.dayOnly(DateTime.now());
    _start = widget.initialStart == null
        ? null
        : BusinessDays.dayOnly(widget.initialStart!);
    _end = widget.initialEnd == null
        ? null
        : BusinessDays.dayOnly(widget.initialEnd!);

    final first = DateTime(widget.firstDate.year, widget.firstDate.month);
    final last = DateTime(widget.lastDate.year, widget.lastDate.month);
    _monthList = <DateTime>[];
    var cursor = first;
    while (!cursor.isAfter(last)) {
      _monthList.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    _monthKeys = List.generate(_monthList.length, (_) => GlobalKey());

    _years = <int>[
      for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
    ];

    final focus = _start ?? now;
    _initialFocus = DateTime(focus.year, focus.month);
    _selectedYearChip = focus.year.clamp(
      widget.firstDate.year,
      widget.lastDate.year,
    );

    _yearChipScroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMonth(_initialFocus, jump: true);
      _scrollYearChipIntoView(_selectedYearChip, jump: true);
    });
  }

  @override
  void dispose() {
    _yearChipScroll.dispose();
    super.dispose();
  }

  int get _workDays {
    if (_start == null || _end == null) return 0;
    return BusinessDays.countInRange(_start!, _end!);
  }

  int _indexOfMonth(DateTime month) {
    final target = DateTime(month.year, month.month);
    return _monthList.indexWhere(
      (m) => m.year == target.year && m.month == target.month,
    );
  }

  void _scrollToMonth(DateTime month, {bool jump = false}) {
    final idx = _indexOfMonth(month);
    if (idx < 0) return;
    setState(() => _selectedYearChip = month.year);

    void go({int attempt = 0}) {
      final ctx = _monthKeys[idx].currentContext;
      if (ctx == null) {
        if (attempt < 8) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => go(attempt: attempt + 1),
          );
        }
        return;
      }
      Scrollable.ensureVisible(
        ctx,
        duration: jump ? Duration.zero : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => go());
  }

  void _scrollYearChipIntoView(int year, {bool jump = false}) {
    final yi = _years.indexOf(year);
    if (yi < 0 || !_yearChipScroll.hasClients) return;
    final offset = (yi * 72.0).clamp(0.0, _yearChipScroll.position.maxScrollExtent);
    if (jump) {
      _yearChipScroll.jumpTo(offset);
    } else {
      _yearChipScroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToYear(int year) {
    _scrollYearChipIntoView(year);
    _scrollToMonth(DateTime(year, 1));
  }

  void _resetSelection() {
    setState(() {
      _start = null;
      _end = null;
      _pickingEnd = false;
    });
  }

  void _onDay(DateTime day) {
    final d = BusinessDays.dayOnly(day);
    if (d.isBefore(BusinessDays.dayOnly(widget.firstDate)) ||
        d.isAfter(BusinessDays.dayOnly(widget.lastDate))) {
      return;
    }
    if (_start == null || !_pickingEnd || d.isBefore(_start!)) {
      setState(() {
        _start = d;
        _end = d;
        _pickingEnd = true;
      });
      return;
    }
    if (_isEgen) {
      final work = BusinessDays.countInRange(_start!, d);
      if (work < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Velg minst én virkedag. Helg og røde dager telles ikke.'),
          ),
        );
        return;
      }
      if (work > widget.maxWorkDays) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Egenmelding kan være maks ${widget.maxWorkDays} virkedager. Velg en kortere periode.',
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      _end = d;
      _pickingEnd = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: h * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Lukk',
                ),
                Expanded(
                  child: Text(
                    _pickingEnd ? 'Velg sluttdato' : 'Velg startdato',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _start == null ? null : _resetSelection,
                  child: const Text('Nullstill'),
                ),
                FilledButton(
                  onPressed: _start == null || _end == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            DateTimeRange(start: _start!, end: _end!),
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Bruk'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _calDateSummary(
                      label: 'Fra',
                      value: _start == null
                          ? '—'
                          : '${_start!.day}. ${_months[_start!.month - 1]}\n${_start!.year}',
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: DriftProTheme.primaryGreen,
                  ),
                  Expanded(
                    child: _calDateSummary(
                      label: 'Til',
                      value: _end == null
                          ? '—'
                          : '${_end!.day}. ${_months[_end!.month - 1]}\n${_end!.year}',
                      alignEnd: true,
                    ),
                  ),
                  if (_start != null && _end != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: DriftProTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_workDays\ndager',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                controller: _yearChipScroll,
                scrollDirection: Axis.horizontal,
                itemCount: _years.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final y = _years[i];
                  final selected = y == _selectedYearChip;
                  return ChoiceChip(
                    label: Text('$y'),
                    selected: selected,
                    onSelected: (_) => _jumpToYear(y),
                    selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? DriftProTheme.primaryGreen
                          : Colors.black87,
                      fontSize: 13,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final w in _weekdays)
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: w == 'Lør' || w == 'Søn'
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            // Eager children så GlobalKey finnes for hopp til år/måned.
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              children: [
                for (var i = 0; i < _monthList.length; i++)
                  KeyedSubtree(
                    key: _monthKeys[i],
                    child: _month(_monthList[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calDateSummary({
    required String label,
    required String value,
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _month(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = first.weekday - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Text(
              '${_months[month.month - 1]} ${month.year}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lead + days,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemBuilder: (_, i) {
              if (i < lead) return const SizedBox.shrink();
              final day = DateTime(month.year, month.month, i - lead + 1);
              return _cell(day);
            },
          ),
        ],
      ),
    );
  }

  Widget _cell(DateTime day) {
    final d = BusinessDays.dayOnly(day);
    final holiday = BusinessDays.holidayName(d);
    final outOfRange = d.isBefore(BusinessDays.dayOnly(widget.firstDate)) ||
        d.isAfter(BusinessDays.dayOnly(widget.lastDate));
    final inRange = !outOfRange &&
        _start != null &&
        _end != null &&
        !d.isBefore(_start!) &&
        !d.isAfter(_end!);
    final edge = !outOfRange && (d == _start || d == _end);
    final work = BusinessDays.isBusinessDay(d);
    return InkWell(
      onTap: outOfRange ? null : () => _onDay(d),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: edge
              ? DriftProTheme.primaryGreen
              : inRange
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.16)
                  : null,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${d.day}',
              style: TextStyle(
                fontWeight: edge || inRange ? FontWeight.w800 : FontWeight.w500,
                color: outOfRange
                    ? Colors.grey.shade300
                    : edge
                        ? Colors.white
                        : (!work ? Colors.grey : Colors.black87),
              ),
            ),
            if (holiday != null && !outOfRange)
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: edge ? Colors.white : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
