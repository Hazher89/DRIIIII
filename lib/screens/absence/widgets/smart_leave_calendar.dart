import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/business_days.dart';
import '../../../models/absence.dart';

/// Norsk kalender. Egenmelding: ett trykk markerer inntil 3 virkedager.
Future<DateTimeRange?> showSmartLeaveCalendar(
  BuildContext context, {
  required AbsenceType type,
  required int maxWorkDays,
  DateTime? initialStart,
  DateTime? initialEnd,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SmartLeaveCalendar(
      type: type,
      maxWorkDays: maxWorkDays,
      initialStart: initialStart,
      initialEnd: initialEnd,
      firstDate: firstDate ?? DateTime(DateTime.now().year - 1),
      lastDate: lastDate ?? DateTime(DateTime.now().year + 2, 12, 31),
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

  late DateTime _anchor;
  DateTime? _start;
  DateTime? _end;
  bool _pickingEnd = false;

  bool get _autoEgen => widget.type == AbsenceType.egenmelding;

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
    _anchor = DateTime((_start ?? now).year, (_start ?? now).month);
  }

  int get _workDays {
    if (_start == null || _end == null) return 0;
    return BusinessDays.countInRange(_start!, _end!);
  }

  void _onDay(DateTime day) {
    final d = BusinessDays.dayOnly(day);
    if (d.isBefore(BusinessDays.dayOnly(widget.firstDate)) ||
        d.isAfter(BusinessDays.dayOnly(widget.lastDate))) {
      return;
    }
    setState(() {
      if (_autoEgen) {
        if (!BusinessDays.isBusinessDay(d)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Egenmelding gjelder virkedager. Helg og røde dager hoppes over.',
              ),
            ),
          );
        }
        _start = d;
        _end = BusinessDays.endAfterBusinessDays(d, widget.maxWorkDays);
        _pickingEnd = false;
        return;
      }
      if (_start == null || _pickingEnd == false || d.isBefore(_start!)) {
        _start = d;
        _end = d;
        _pickingEnd = true;
        return;
      }
      _end = d;
      _pickingEnd = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: h * 0.88,
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
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    _autoEgen
                        ? 'Egenmelding · maks ${widget.maxWorkDays} virkedager'
                        : 'Velg periode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: _start == null || _end == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            DateTimeRange(start: _start!, end: _end!),
                          ),
                  child: const Text('Bruk'),
                ),
              ],
            ),
          ),
          if (_start != null && _end != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                _autoEgen
                    ? '$_workDays virkedager markert automatisk'
                    : '$_workDays virkedager i perioden',
                style: TextStyle(
                  color: DriftProTheme.primaryGreen,
                  fontWeight: FontWeight.w700,
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              children: [
                for (var i = 0; i < 4; i++)
                  _month(DateTime(_anchor.year, _anchor.month + i)),
              ],
            ),
          ),
        ],
      ),
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
    final weekend = BusinessDays.isWeekend(d);
    final inRange = _start != null &&
        _end != null &&
        !d.isBefore(_start!) &&
        !d.isAfter(_end!);
    final edge = d == _start || d == _end;
    final work = BusinessDays.isBusinessDay(d);
    return InkWell(
      onTap: () => _onDay(d),
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
                color: edge
                    ? Colors.white
                    : (!work ? Colors.grey : Colors.black87),
                decoration: weekend || holiday != null
                    ? TextDecoration.none
                    : null,
              ),
            ),
            if (holiday != null)
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
