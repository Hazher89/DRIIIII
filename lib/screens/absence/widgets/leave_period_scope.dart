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

  @override
  void initState() {
    super.initState();
    _mode = widget.initial.mode;
    _year = widget.initial.year;
    _from = widget.initial.rangeStart;
    _to = widget.initial.rangeEnd;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: VacationYearWindow.earliestSelectableDate,
      lastDate: VacationYearWindow.latestSelectableDate,
      locale: const Locale('nb', 'NO'),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMMM yyyy', 'nb_NO');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
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
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == LeavePeriodMode.year)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final y in VacationYearWindow.years.reversed.take(8))
                  ChoiceChip(
                    label: Text('$y'),
                    selected: y == _year,
                    onSelected: (_) => setState(() => _year = y),
                    selectedColor:
                        DriftProTheme.primaryGreen.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      fontWeight: y == _year ? FontWeight.w900 : FontWeight.w600,
                      color: y == _year ? DriftProTheme.primaryGreen : null,
                    ),
                  ),
              ],
            )
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fra og med'),
              subtitle: Text(df.format(_from)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () => _pickDate(isFrom: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Til og med'),
              subtitle: Text(df.format(_to)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () => _pickDate(isFrom: false),
            ),
          ],
          const SizedBox(height: 16),
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
    );
  }
}
