import 'package:flutter/material.dart';

import '../../core/constants/leave_rules.dart';
import '../../core/services/absence/absence_service.dart';
import '../../core/services/absence/department_leave_conflict_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';
import 'widgets/department_leave_tip_card.dart';
import 'widgets/leave_rules_panel.dart';

class NewAbsenceScreen extends StatefulWidget {
  final AbsenceType type;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final bool allowPickEmployee;

  const NewAbsenceScreen({
    super.key,
    required this.type,
    this.initialStart,
    this.initialEnd,
    this.allowPickEmployee = false,
  });

  @override
  State<NewAbsenceScreen> createState() => _NewAbsenceScreenState();
}

class _NewAbsenceScreenState extends State<NewAbsenceScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  UserProfile? _profile;
  List<UserProfile> _selectableEmployees = [];
  UserProfile? _selectedEmployee;

  AbsenceQuota? _quota;
  CompanyLeaveSettings _companySettings = const CompanyLeaveSettings();
  List<DepartmentLeaveOverlap> _overlaps = [];
  String? _departmentName;
  int _childrenCount = 1;
  bool _isLoadingContext = true;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStart;
    _endDate = widget.initialEnd ?? widget.initialStart;
    _loadContext();
  }

  Future<void> _loadContext() async {
    setState(() => _isLoadingContext = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile == null || profile.companyId == null) return;

      _profile = profile;
      _selectedEmployee = profile;

      if (widget.allowPickEmployee && (profile.isLeader || profile.isAdmin)) {
        final all = await SupabaseService.fetchProfiles(companyId: profile.companyId);
        _selectableEmployees = profile.isAdmin
            ? all.where((p) => !p.isPartnerPortalUser && p.isActive).toList()
            : all
                .where((p) =>
                    p.departmentId == profile.departmentId &&
                    !p.isPartnerPortalUser &&
                    p.isActive)
                .toList();
        if (!_selectableEmployees.any((p) => p.id == profile.id)) {
          _selectableEmployees = [profile, ..._selectableEmployees];
        }
      } else {
        _selectableEmployees = [profile];
      }

      _companySettings =
          await SupabaseService.fetchCompanyLeaveSettings(profile.companyId!);
      await _loadQuotaForSelected();
    } finally {
      if (mounted) setState(() => _isLoadingContext = false);
    }
  }

  Future<void> _loadQuotaForSelected() async {
    if (_selectedEmployee == null) return;
    final year = _startDate?.year ?? DateTime.now().year;
    try {
      final quota = await SupabaseService.ensureAbsenceQuota(
        userId: _selectedEmployee!.id,
        companyId: _profile!.companyId!,
        year: year,
      );
      if (mounted) setState(() => _quota = quota);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _isSelfRequest => _selectedEmployee?.id == _profile?.id;

  bool get _managerRegistersForOther =>
      !_isSelfRequest && (_profile?.isLeader == true || _profile?.isAdmin == true);

  Future<void> _checkConflicts() async {
    if (_startDate == null ||
        _endDate == null ||
        _selectedEmployee?.departmentId == null ||
        _profile?.companyId == null) {
      return;
    }

    final deptId = _selectedEmployee!.departmentId!;
    final absences = await SupabaseService.fetchAbsences(
      departmentId: deptId,
    );
    final depts = await SupabaseService.fetchDepartments(
      companyId: _profile!.companyId!,
    );
    String? deptName;
    for (final d in depts) {
      if (d.id == deptId) {
        deptName = d.name;
        break;
      }
    }

    final overlaps = DepartmentLeaveConflictService.findOverlaps(
      departmentId: deptId,
      startDate: _startDate!,
      endDate: _endDate!,
      pool: absences,
      excludeUserId: _selectedEmployee!.id,
      vacationOnly: widget.type == AbsenceType.ferie,
    );

    if (mounted) {
      setState(() {
        _overlaps = overlaps;
        _departmentName = deptName;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: DriftProTheme.primaryGreen,
              primary: DriftProTheme.primaryGreen,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadQuotaForSelected();
      _checkConflicts();
    }
  }

  Future<void> _submit() async {
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Velg tidsperiode.');
      return;
    }
    if (_selectedEmployee == null || _profile == null) return;

    final validationError = AbsenceService.validateRequest(
      type: widget.type,
      start: _startDate!,
      end: _endDate!,
      quota: _quota,
      company: _companySettings,
      childrenCount: _childrenCount,
    );
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final status = _managerRegistersForOther
          ? AbsenceStatus.godkjent
          : AbsenceStatus.ventende;

      final absence = Absence(
        id: 'temp',
        userId: _selectedEmployee!.id,
        companyId: _profile!.companyId!,
        departmentId: _selectedEmployee!.departmentId,
        type: widget.type,
        startDate: _startDate!,
        endDate: _endDate!,
        status: status,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
        quotaYear: _startDate!.year,
      );

      await SupabaseService.createAbsence(
        absence,
        approverId: _managerRegistersForOther ? _profile!.id : null,
      );

      if (!mounted) return;
      final msg = status == AbsenceStatus.godkjent
          ? 'Fravær registrert og godkjent.'
          : 'Søknad sendt. Leder og admin får beskjed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Kunne ikke lagre: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalDays = _startDate != null && _endDate != null
        ? AbsenceService.dayCount(_startDate!, _endDate!)
        : 0;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text('Registrer ${widget.type.label.toLowerCase()}'),
      ),
      body: _isLoadingContext
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.allowPickEmployee && _selectableEmployees.length > 1) ...[
                    _sectionHeader('Gjelder ansatt', isDark),
                    const SizedBox(height: 12),
                    _buildEmployeeSelector(isDark),
                    const SizedBox(height: 24),
                  ],
                  if (widget.type == AbsenceType.ferie && _quota != null)
                    _buildQuotaInfo(isDark, totalDays),
                  if (widget.type == AbsenceType.syktBarn) ...[
                    _sectionHeader('Antall barn under 12 år', isDark),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1 barn')),
                        ButtonSegment(value: 2, label: Text('2+')),
                      ],
                      selected: {_childrenCount >= 2 ? 2 : 1},
                      onSelectionChanged: (s) {
                        setState(() => _childrenCount = s.first);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  _sectionHeader('Tidsperiode', isDark),
                  const SizedBox(height: 12),
                  _buildDatePickerCard(isDark, totalDays),
                  if (_overlaps.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DepartmentLeaveTipCard(
                      overlaps: _overlaps,
                      departmentName: _departmentName,
                      isApprovalContext:
                          _managerRegistersForOther && widget.type == AbsenceType.ferie,
                    ),
                  ],
                  const SizedBox(height: 20),
                  LeaveRulesPanel(highlightType: widget.type, compact: true),
                  const SizedBox(height: 20),
                  _sectionHeader('Kommentar (valgfritt)', isDark),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _commentController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Utfyllende informasjon…',
                      fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              (_isSelfRequest ? 'Send søknad' : 'Registrer og godkjenn')
                                  .toUpperCase(),
                              style: const TextStyle(
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildEmployeeSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserProfile>(
          isExpanded: true,
          value: _selectedEmployee,
          items: _selectableEmployees
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e.id == _profile?.id ? 'Meg selv (${e.fullName})' : e.fullName,
                  ),
                ),
              )
              .toList(),
          onChanged: (val) {
            setState(() => _selectedEmployee = val);
            _loadQuotaForSelected();
            _checkConflicts();
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Text(
      title.toUpperCase(),
      style: DriftProTheme.labelSm.copyWith(
        color: isDark ? Colors.grey[500] : Colors.grey[600],
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildQuotaInfo(bool isDark, int requestedDays) {
    final remaining = _quota!.vacationDaysRemaining;
    final after = remaining - requestedDays;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Feriebalanse ${_quota!.year}',
            style: DriftProTheme.labelSm.copyWith(color: DriftProTheme.primaryGreen),
          ),
          const SizedBox(height: 8),
          Text(
            'Tildelt ${ _quota!.vacationDaysTotal} + overført ${_quota!.vacationDaysCarriedOver} '
            '− brukt ${_quota!.vacationDaysUsed} = $remaining igjen',
            style: DriftProTheme.bodySm,
          ),
          if (requestedDays > 0)
            Text(
              after >= 0
                  ? 'Etter denne søknaden: $after dager igjen.'
                  : 'Advarsel: du søker $requestedDays dager, men har bare $remaining igjen.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: after >= 0 ? DriftProTheme.primaryGreen : DriftProTheme.error,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDatePickerCard(bool isDark, int totalDays) {
    return GestureDetector(
      onTap: _pickDateRange,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
          ),
          boxShadow: DriftProTheme.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fra – til', style: DriftProTheme.caption),
                  const SizedBox(height: 4),
                  Text(
                    _startDate != null && _endDate != null
                        ? '${_startDate!.day}. ${_month(_startDate!.month)} – '
                            '${_endDate!.day}. ${_month(_endDate!.month)}'
                        : 'Velg dager',
                    style: DriftProTheme.headingSm.copyWith(fontSize: 18),
                  ),
                ],
              ),
            ),
            if (totalDays > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalDays dager',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.calendar_today_rounded,
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  String _month(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun',
      'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return names[m - 1];
  }
}
