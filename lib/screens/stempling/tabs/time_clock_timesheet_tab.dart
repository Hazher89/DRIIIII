import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/time_clock/time_clock_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/time_clock/time_overtime_summary.dart';
import '../../../models/time_clock/time_timesheet_entry.dart';
import '../../../models/time_clock/time_work_type.dart';
import '../../../models/user_profile.dart';
import '../../employees/employee_access_detail_screen.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/time_clock_entry_sheet.dart';
import '../widgets/time_clock_overtime_panel.dart';

class TimeClockTimesheetTab extends StatefulWidget {
  const TimeClockTimesheetTab({
    super.key,
    required this.profile,
    required this.canEditAll,
  });

  final UserProfile profile;
  final bool canEditAll;

  @override
  State<TimeClockTimesheetTab> createState() => _TimeClockTimesheetTabState();
}

class _TimeClockTimesheetTabState extends State<TimeClockTimesheetTab> {
  List<UserProfile> _employees = [];
  List<Department> _departments = [];
  List<TimeWorkType> _workTypes = [];
  List<TimeTimesheetEntry> _entries = [];
  TimeOvertimeSummary? _overtime;
  String? _selectedProfileId;
  DateTime _weekStart = _mondayOf(DateTime.now());
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _employeeSearch = '';

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  UserProfile? get _selectedEmployee {
    if (_selectedProfileId == null) return null;
    for (final e in _employees) {
      if (e.id == _selectedProfileId) return e;
    }
    return null;
  }

  List<UserProfile> get _filteredEmployees {
    final q = _employeeSearch.trim().toLowerCase();
    if (q.isEmpty) return _employees;
    return _employees
        .where((e) =>
            e.fullName.toLowerCase().contains(q) ||
            (e.employeeNumber ?? '').contains(q))
        .toList();
  }

  double get _weekTotal => _entries.fold(0.0, (s, e) => s + e.hours);

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companyId = widget.profile.companyId;
      if (companyId == null) throw Exception('Mangler bedrift');

      final employees = await SupabaseService.fetchProfiles(companyId: companyId);
      final workTypes = await TimeClockService.fetchWorkTypes(companyId);
      final depts = await SupabaseService.fetchDepartments(companyId: companyId);

      final scoped = employees.where((e) {
        if (e.id == widget.profile.id && !widget.canEditAll) return false;
        if (widget.canEditAll || widget.profile.isSuperAdmin || widget.profile.isAdmin) {
          return e.partnerId == null;
        }
        return e.departmentId == widget.profile.departmentId;
      }).toList();

      scoped.sort((a, b) => a.fullName.compareTo(b.fullName));

      if (!mounted) return;
      setState(() {
        _employees = scoped;
        _departments = depts;
        _workTypes = workTypes;
        _selectedProfileId ??= scoped.isNotEmpty ? scoped.first.id : null;
        _loading = false;
      });
      if (_selectedProfileId != null) await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke laste timeliste';
        _loading = false;
      });
    }
  }

  Future<void> _loadEntries() async {
    final pid = _selectedProfileId;
    if (pid == null) return;
    setState(() => _loading = true);
    try {
      final entries = await TimeClockService.fetchTimesheetEntries(
        profileId: pid,
        weekStart: _weekStart,
        weekEnd: _weekEnd,
      );
      final overtime = await TimeClockService.fetchOvertimeSummary(
        profileId: pid,
        weekStart: _weekStart,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _overtime = overtime;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunne ikke laste timer';
        _loading = false;
      });
    }
  }

  Future<void> _saveEntry(TimeTimesheetEntry entry) async {
    setState(() => _saving = true);
    try {
      await TimeClockService.upsertEntry(entry);
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lagring feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEntrySheet({TimeTimesheetEntry? entry, required DateTime day}) async {
    final pid = _selectedProfileId;
    final companyId = widget.profile.companyId;
    if (pid == null || companyId == null || _workTypes.isEmpty) return;

    final result = await TimeClockEntrySheet.show(
      context,
      entry: entry,
      workDate: day,
      profileId: pid,
      companyId: companyId,
      workTypes: _workTypes,
    );
    if (result != null) await _saveEntry(result);
  }

  Future<void> _deleteEntry(TimeTimesheetEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett registrering?'),
        content: const Text('Timeregistreringen fjernes permanent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true || entry.id.isEmpty) return;
    setState(() => _saving = true);
    try {
      await TimeClockService.deleteEntry(entry.id);
      await _loadEntries();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEmployeeProfile() async {
    final employee = _selectedEmployee;
    if (employee == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeAccessDetailScreen(
          employee: employee,
          departments: _departments,
          isSuperAdmin: widget.profile.isSuperAdmin,
          canEditProfile: widget.profile.isSuperAdmin || widget.profile.access.canEditEmployees,
        ),
      ),
    );
  }

  Map<String, double> _sumByWorkType() {
    final map = <String, double>{};
    for (final e in _entries) {
      final key = '${e.workTypeCode ?? ''} ${e.workTypeName ?? ''}'.trim();
      map[key] = (map[key] ?? 0) + e.hours;
    }
    return map;
  }

  Map<String, double> _sumByPayroll() {
    final map = <String, double>{};
    for (final e in _entries) {
      final key = e.payrollCode ?? '—';
      map[key] = (map[key] ?? 0) + e.hours;
    }
    return map;
  }

  double _dayTotal(DateTime day) {
    return _entries
        .where((e) =>
            e.workDate.year == day.year &&
            e.workDate.month == day.month &&
            e.workDate.day == day.day)
        .fold(0.0, (s, e) => s + e.hours);
  }

  List<TimeTimesheetEntry> _dayEntries(DateTime day) {
    return _entries
        .where((e) =>
            e.workDate.year == day.year &&
            e.workDate.month == day.month &&
            e.workDate.day == day.day)
        .toList();
  }

  void _shiftWeek(int delta) {
    _weekStart = _weekStart.add(Duration(days: 7 * delta));
    setState(() {});
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _entries.isEmpty && _employees.isEmpty) {
      return const DriftProLoadingPage();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final weekLabel =
        '${DateFormat('d. MMM', 'nb').format(_weekStart)} – ${DateFormat('d. MMM yyyy', 'nb').format(_weekEnd)}';
    final weekNo = DateFormat('w').format(_weekStart);
    final employee = _selectedEmployee;

    return Column(
      children: [
        _header(isDark, weekLabel, weekNo, employee),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
          ),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _selectedProfileId == null
              ? const Center(child: Text('Ingen ansatte å vise'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (_overtime != null) ...[
                      TimeClockOvertimePanel(summary: _overtime!),
                      const SizedBox(height: 16),
                    ],
                    _summaryRow(isDark),
                    const SizedBox(height: 16),
                    for (var i = 0; i < 7; i++)
                      _dayCard(_weekStart.add(Duration(days: i)), isDark),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _header(bool isDark, String weekLabel, String weekNo, UserProfile? employee) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade300.withValues(alpha: 0.6))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 800;
            final employeePicker = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Autocomplete<UserProfile>(
                  initialValue: TextEditingValue(text: employee?.fullName ?? ''),
                  optionsBuilder: (text) {
                    _employeeSearch = text.text;
                    return _filteredEmployees;
                  },
                  displayStringForOption: (u) => u.fullName,
                  onSelected: (u) {
                    setState(() => _selectedProfileId = u.id);
                    _loadEntries();
                  },
                  fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Ansatt',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        suffixIcon: employee != null
                            ? IconButton(
                                tooltip: 'Åpne ansattprofil',
                                icon: const Icon(Icons.open_in_new, size: 20),
                                onPressed: _openEmployeeProfile,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ],
            );

            final weekNav = Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Forrige uke',
                    onPressed: () => _shiftWeek(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Column(
                    children: [
                      Text(weekLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Uke $weekNo', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Neste uke',
                    onPressed: () => _shiftWeek(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: () {
                      _weekStart = _mondayOf(DateTime.now());
                      setState(() {});
                      _loadEntries();
                    },
                    child: const Text('I dag'),
                  ),
                ],
              ),
            );

            final totalBadge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text('Uke totalt', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(
                    '${_weekTotal.toStringAsFixed(1)} t',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 3, child: employeePicker),
                  const SizedBox(width: 16),
                  weekNav,
                  const SizedBox(width: 16),
                  totalBadge,
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                employeePicker,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: weekNav),
                    const SizedBox(width: 12),
                    totalBadge,
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryRow(bool isDark) {
    final byType = _sumByWorkType();
    final byPayroll = _sumByPayroll();

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 700;
        final children = [
          Expanded(child: _summaryCard('Arbeidstype', byType, isDark)),
          const SizedBox(width: 12, height: 12),
          Expanded(child: _summaryCard('Lønnsart', byPayroll, isDark)),
        ];
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }
        return Column(children: children);
      },
    );
  }

  Widget _summaryCard(String title, Map<String, double> data, bool isDark) {
    return Card(
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (data.isEmpty)
              Text('Ingen timer', style: TextStyle(fontSize: 13, color: Colors.grey.shade600))
            else
              ...data.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.key, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        '${e.value.toStringAsFixed(2)} t',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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

  Widget _dayCard(DateTime day, bool isDark) {
    final entries = _dayEntries(day);
    final total = _dayTotal(day);
    final isToday = _isToday(day);
    final dayName = DateFormat('EEEE', 'nb').format(day);
    final dateLabel = DateFormat('d. MMM', 'nb').format(day);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isToday
              ? DriftProTheme.primaryGreen.withValues(alpha: 0.5)
              : Colors.grey.shade300.withValues(alpha: 0.5),
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('I dag', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                Text(
                  dayName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Text(dateLabel, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const Spacer(),
                Text(
                  '${total.toStringAsFixed(2)} t',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: total > 0 ? DriftProTheme.primaryGreen : Colors.grey.shade500,
                  ),
                ),
                IconButton(
                  tooltip: 'Legg til timer',
                  onPressed: () => _openEntrySheet(day: day),
                  icon: const Icon(Icons.add_circle_outline),
                  color: DriftProTheme.primaryGreen,
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ingen registreringer',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            )
          else ...[
            const Divider(height: 1),
            _entryTableHeader(),
            ...entries.map((e) => _entryRow(e)),
          ],
        ],
      ),
    );
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  Widget _entryTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.grey.shade100.withValues(alpha: 0.5),
      child: Row(
        children: [
          _colHeader('Type', flex: 3),
          _colHeader('Fra', flex: 2),
          _colHeader('Til', flex: 2),
          _colHeader('Timer', flex: 2),
          _colHeader('OT', flex: 1),
          _colHeader('Notat', flex: 3),
          const SizedBox(width: 72),
        ],
      ),
    );
  }

  Widget _colHeader(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _entryRow(TimeTimesheetEntry entry) {
    final wt = _workTypes.cast<TimeWorkType?>().firstWhere(
          (t) => t?.id == entry.workTypeId,
          orElse: () => null,
        );
    final locked = entry.isLocked;

    return InkWell(
      onTap: locked ? null : () => _openEntrySheet(entry: entry, day: entry.workDate),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: wt?.color ?? DriftProTheme.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      wt?.label ?? entry.workTypeName ?? '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(_shortTime(entry.startTime), style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Text(_shortTime(entry.endTime), style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${entry.hours.toStringAsFixed(2)} t',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 1,
              child: entry.overtimeHours > 0
                  ? Text(
                      '+${entry.overtimeHours.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    )
                  : Text('—', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                entry.overtimeReason ?? entry.note ?? entry.project ?? entry.activity ?? '—',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (locked)
                    Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade500)
                  else ...[
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _openEntrySheet(entry: entry, day: entry.workDate),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.delete_outline, size: 18, color: DriftProTheme.error),
                      onPressed: () => _deleteEntry(entry),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }
}
