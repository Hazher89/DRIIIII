import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/vacation_year_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/business_days.dart';
import '../../../models/absence.dart';

enum LeavePeriodMode { year, range }

/// Valgt år eller fri periode for ansatt-/eksportvisning.
class LeavePeriodScope {
  final LeavePeriodMode mode;
  final int year;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  const LeavePeriodScope._({
    required this.mode,
    required this.year,
    required this.rangeStart,
    required this.rangeEnd,
  });

  factory LeavePeriodScope.year(int year) {
    return LeavePeriodScope._(
      mode: LeavePeriodMode.year,
      year: year,
      rangeStart: DateTime(year, 1, 1),
      rangeEnd: DateTime(year, 12, 31),
    );
  }

  factory LeavePeriodScope.range(DateTime start, DateTime end) {
    final s = BusinessDays.dayOnly(start);
    final e = BusinessDays.dayOnly(end);
    final orderedStart = s.isAfter(e) ? e : s;
    final orderedEnd = s.isAfter(e) ? s : e;
    return LeavePeriodScope._(
      mode: LeavePeriodMode.range,
      year: orderedStart.year,
      rangeStart: orderedStart,
      rangeEnd: orderedEnd,
    );
  }

  factory LeavePeriodScope.current() => LeavePeriodScope.year(DateTime.now().year);

  String get label {
    if (mode == LeavePeriodMode.year) return '$year';
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    return '${df.format(rangeStart)} – ${df.format(rangeEnd)}';
  }

  String get shortLabel {
    if (mode == LeavePeriodMode.year) return 'År $year';
    final df = DateFormat('dd.MM.yy');
    return '${df.format(rangeStart)}–${df.format(rangeEnd)}';
  }

  bool overlaps(Absence a) {
    final s = BusinessDays.dayOnly(a.startDate);
    final e = BusinessDays.dayOnly(a.endDate);
    return !e.isBefore(rangeStart) && !s.isAfter(rangeEnd);
  }

  List<Absence> filter(List<Absence> absences) =>
      absences.where(overlaps).toList();

  /// Referansedato for kvote-/periodeberegning.
  DateTime get referenceDate {
    final now = DateTime.now();
    if (mode == LeavePeriodMode.year) {
      if (year < now.year) return DateTime(year, 12, 31);
      if (year > now.year) return DateTime(year, 1, 1);
      return now;
    }
    if (rangeEnd.isBefore(BusinessDays.dayOnly(now))) return rangeEnd;
    if (rangeStart.isAfter(BusinessDays.dayOnly(now))) return rangeStart;
    return now;
  }
}

/// Én knapp/chip som åpner år- eller periodevelger.
class LeavePeriodScopeButton extends StatelessWidget {
  const LeavePeriodScopeButton({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  final LeavePeriodScope scope;
  final ValueChanged<LeavePeriodScope> onChanged;

  Future<void> _open(BuildContext context) async {
    final result = await showLeavePeriodScopeSheet(context, initial: scope);
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? DriftProTheme.dividerDark
                  : DriftProTheme.primaryGreen.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range_rounded,
                size: 18,
                color: DriftProTheme.primaryGreen,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  scope.shortLabel,
                  style: DriftProTheme.labelMd.copyWith(
                    fontWeight: FontWeight.w800,
                    color: DriftProTheme.primaryGreen,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<LeavePeriodScope?> showLeavePeriodScopeSheet(
  BuildContext context, {
  required LeavePeriodScope initial,
}) {
  return showModalBottomSheet<LeavePeriodScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _LeavePeriodScopeSheet(initial: initial),
  );
}

class _LeavePeriodScopeSheet extends StatefulWidget {
  const _LeavePeriodScopeSheet({required this.initial});

  final LeavePeriodScope initial;

  @override
  State<_LeavePeriodScopeSheet> createState() => _LeavePeriodScopeSheetState();
}

class _LeavePeriodScopeSheetState extends State<_LeavePeriodScopeSheet> {
  late LeavePeriodMode _mode;
  late int _year;
  late DateTime _from;
  late DateTime _to;
  /// null = ingen kalender · true = rediger «fra» · false = rediger «til»
  bool? _editingFrom;

  DateTime get _first => VacationYearWindow.earliestSelectableDate;
  DateTime get _last => VacationYearWindow.latestSelectableDate;

  DateTime _clampDate(DateTime d) {
    final day = BusinessDays.dayOnly(d);
    if (day.isBefore(_first)) return _first;
    if (day.isAfter(_last)) return _last;
    return day;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initial.mode;
    _year = widget.initial.year.clamp(
      VacationYearWindow.fromYear,
      VacationYearWindow.toYear,
    );
    _from = _clampDate(widget.initial.rangeStart);
    _to = _clampDate(widget.initial.rangeEnd);
    if (_to.isBefore(_from)) _to = _from;
  }

  void _setDate(DateTime picked) {
    final day = _clampDate(picked);
    setState(() {
      if (_editingFrom == true) {
        _from = day;
        if (_to.isBefore(_from)) _to = _from;
      } else if (_editingFrom == false) {
        _to = day;
        if (_to.isBefore(_from)) _from = _to;
      }
      _editingFrom = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMMM yyyy', 'nb_NO');
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Velg periode',
                style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Vis saldo og fravær for ett år, eller et valgfritt intervall.',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 16),
              SegmentedButton<LeavePeriodMode>(
                segments: const [
                  ButtonSegment(
                    value: LeavePeriodMode.year,
                    label: Text('År'),
                    icon: Icon(Icons.calendar_today_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: LeavePeriodMode.range,
                    label: Text('Fra–til'),
                    icon: Icon(Icons.date_range_outlined, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _editingFrom = null;
                }),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: _mode == LeavePeriodMode.year
                      ? Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final y in VacationYearWindow.yearsNewestFirst)
                              ChoiceChip(
                                label: Text('$y'),
                                selected: y == _year,
                                onSelected: (_) => setState(() => _year = y),
                                selectedColor: DriftProTheme.primaryGreen
                                    .withValues(alpha: 0.2),
                                labelStyle: TextStyle(
                                  fontWeight: y == _year
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: y == _year
                                      ? DriftProTheme.primaryGreen
                                      : null,
                                ),
                              ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RangeDateTile(
                              label: 'Fra og med',
                              value: df.format(_from),
                              selected: _editingFrom == true,
                              onTap: () => setState(
                                () => _editingFrom =
                                    _editingFrom == true ? null : true,
                              ),
                            ),
                            _RangeDateTile(
                              label: 'Til og med',
                              value: df.format(_to),
                              selected: _editingFrom == false,
                              onTap: () => setState(
                                () => _editingFrom =
                                    _editingFrom == false ? null : false,
                              ),
                            ),
                            if (_editingFrom != null) ...[
                              const SizedBox(height: 8),
                              // Inline kalender — unngår nestet showDatePicker
                              // som blir grå/usynlig over bottom sheet på web.
                              Material(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? DriftProTheme.cardDark
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                child: CalendarDatePicker(
                                  initialDate:
                                      _editingFrom! ? _from : _to,
                                  firstDate: _first,
                                  lastDate: _last,
                                  currentDate: DateTime.now(),
                                  onDateChanged: _setDate,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final scope = _mode == LeavePeriodMode.year
                      ? LeavePeriodScope.year(_year)
                      : LeavePeriodScope.range(_from, _to);
                  Navigator.pop(context, scope);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Bruk periode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeDateTile extends StatelessWidget {
  const _RangeDateTile({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
            : (isDark ? DriftProTheme.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? DriftProTheme.primaryGreen
                    : (isDark
                        ? DriftProTheme.dividerDark
                        : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: DriftProTheme.labelMd.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.expand_less_rounded
                      : Icons.edit_calendar_outlined,
                  color: DriftProTheme.primaryGreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
