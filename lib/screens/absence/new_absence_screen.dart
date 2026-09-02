import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/leave_rules.dart';
import '../../core/constants/vacation_year_window.dart';
import '../../core/services/absence/absence_service.dart';
import '../../core/services/absence/leave_eligibility.dart';
import '../../core/services/absence/leave_period_usage_service.dart';
import '../../models/leave_period_usage.dart';
import '../../core/utils/business_days.dart';
import '../../core/services/absence/department_leave_conflict_service.dart';
import '../../core/services/nav_badge_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';
import 'widgets/department_leave_tip_card.dart';
import 'widgets/leave_rules_panel.dart';
import 'widgets/leave_usage_meter.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class NewAbsenceScreen extends StatefulWidget {
  final AbsenceType type;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final bool allowPickEmployee;
  /// Rediger ventende egen søknad.
  final Absence? existingAbsence;

  const NewAbsenceScreen({
    super.key,
    required this.type,
    this.initialStart,
    this.initialEnd,
    this.allowPickEmployee = false,
    this.existingAbsence,
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
  Map<int, AbsenceQuota> _quotasByYear = {};
  LeavePeriodUsage? _periodUsage;
  CompanyLeaveSettings _companySettings = const CompanyLeaveSettings();
  List<DepartmentLeaveOverlap> _overlaps = [];
  String? _departmentName;
  bool _isLoadingContext = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAbsence;
    _startDate = existing?.startDate ?? widget.initialStart;
    _endDate = existing?.endDate ?? widget.initialEnd ?? widget.initialStart;
    if (existing?.comment != null) {
      _commentController.text = existing!.comment!;
    }
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
        if (profile.role == UserRole.leder) {
          _selectableEmployees =
              _selectableEmployees.where((p) => p.id != profile.id).toList();
        } else if (!_selectableEmployees.any((p) => p.id == profile.id)) {
          _selectableEmployees = [profile, ..._selectableEmployees];
        }
        if (_selectableEmployees.isNotEmpty) {
          _selectedEmployee = _selectableEmployees.first;
        } else if (profile.role == UserRole.leder) {
          _error =
              'Ingen ansatte i din avdeling å registrere fravær for. Avdelingsleder kan ikke registrere egen ferie/fravær.';
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
    final years = _startDate != null && _endDate != null
        ? BusinessDays.yearsSpanned(_startDate!, _endDate!)
        : <int>[VacationYearWindow.currentYear];
    try {
      final quotas = <int, AbsenceQuota>{};
      for (final year in years) {
        quotas[year] = await SupabaseService.ensureAbsenceQuota(
          userId: _selectedEmployee!.id,
          companyId: _profile!.companyId!,
          year: year,
        );
      }
      final absences = await SupabaseService.fetchAbsences(
        userId: _selectedEmployee!.id,
      );
      final periodUsage = LeavePeriodUsageService.compute(
        absences: absences,
        hireDate: _selectedEmployee!.hireDate,
        referenceDate: _startDate,
        includePending: true,
      );
      if (mounted) {
        setState(() {
          _quotasByYear = quotas;
          _quota = quotas[years.last];
          _periodUsage = periodUsage;
        });
      }
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
  bool get _leaderSelfBlocked =>
      _profile?.role == UserRole.leder && _isSelfRequest;

  bool get _managerRegistersForOther =>
      !_isSelfRequest && (_profile?.isLeader == true || _profile?.isAdmin == true);

  /// Superadmin registrerer direkte (ikke søknad). Leder/admin for andre godkjenner samtidig.
  bool get _directRegister =>
      _managerRegistersForOther ||
      (_profile?.role == UserRole.superadmin && widget.allowPickEmployee);

  bool get _egenmeldingBlocked =>
      widget.type == AbsenceType.egenmelding &&
      _periodUsage != null &&
      LeaveEligibility.isEgenmeldingExhausted(
        usage: _periodUsage,
        maxDays: _companySettings.egenmeldingDaysPerYear,
      );

  int get _childrenUnder12 => _selectedEmployee?.childrenUnder12Count ?? 0;

  String get _submitButtonLabel {
    if (_profile?.role == UserRole.superadmin && widget.allowPickEmployee) {
      return 'Lagre';
    }
    if (_managerRegistersForOther) return 'Registrer og godkjenn';
    return 'Send søknad';
  }

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
    final maxConsec = _companySettings.effectiveEgenmeldingConsecutiveMax;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: VacationYearWindow.earliestSelectableDate,
      lastDate: VacationYearWindow.latestSelectableDate,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(start: now, end: now),
      helpText: widget.type == AbsenceType.egenmelding
          ? 'Egenmelding: maks $maxConsec dager'
          : 'Velg periode',
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
      var start = picked.start;
      var end = picked.end;
      if (widget.type == AbsenceType.egenmelding) {
        final days = AbsenceService.dayCount(start, end);
        if (days > maxConsec) {
          end = start.add(Duration(days: maxConsec - 1));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Egenmelding begrenset til maks $maxConsec dager. Perioden er justert.',
                ),
              ),
            );
          }
        }
      }
      setState(() {
        _startDate = start;
        _endDate = end;
        _error = null;
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
    if (_leaderSelfBlocked) {
      setState(() => _error =
          'Avdelingsleder kan ikke registrere eller endre egen ferie/fravær. Kontakt superadmin.');
      return;
    }

    final validationError = AbsenceService.validateRequest(
      type: widget.type,
      start: _startDate!,
      end: _endDate!,
      quota: _quota,
      quotasByYear: widget.type == AbsenceType.ferie ? _quotasByYear : null,
      periodUsage: _periodUsage,
      company: _companySettings,
      childrenUnder12: _childrenUnder12,
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
      final existing = widget.existingAbsence;
      if (existing != null) {
        if (existing.status != AbsenceStatus.ventende) {
          throw StateError('Kun ventende søknader kan endres.');
        }
        await SupabaseService.updatePendingAbsence(
          id: existing.id,
          type: widget.type,
          startDate: _startDate!,
          endDate: _endDate!,
          comment: _commentController.text.trim().isEmpty
              ? null
              : _commentController.text.trim(),
          quotaYear: _startDate!.year,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Søknaden er oppdatert')),
        );
        Navigator.of(context).pop(true);
        return;
      }

      final status = _directRegister
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
        approverId: _directRegister ? _profile!.id : null,
      );
      unawaited(NavBadgeService.refresh());

      if (!mounted) return;
      final msg = status == AbsenceStatus.godkjent
          ? (_profile?.role == UserRole.superadmin && widget.allowPickEmployee
              ? '${widget.type.label} lagret.'
              : 'Fravær registrert og godkjent.')
          : 'Søknad sendt. Leder og admin får beskjed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Kunne ikke lagre: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool get _canSeeRules =>
      _profile?.isAdmin == true ||
      _profile?.isLeader == true ||
      _profile?.role == UserRole.superadmin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalDays = _startDate != null && _endDate != null
        ? (widget.type == AbsenceType.ferie
            ? AbsenceService.vacationDayCount(_startDate!, _endDate!)
            : AbsenceService.dayCount(_startDate!, _endDate!))
        : 0;
    final maxConsec = _companySettings.effectiveEgenmeldingConsecutiveMax;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(
          widget.existingAbsence != null
              ? 'Endre ${widget.type.label.toLowerCase()}'
              : 'Søk ${widget.type.label.toLowerCase()}',
        ),
      ),
      body: _isLoadingContext
          ? const DriftProLoadingCenter()
          : _egenmeldingBlocked
              ? _buildEgenmeldingBlockedBody(isDark)
              : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.allowPickEmployee && _selectableEmployees.length > 1) ...[
                    _sectionHeader('Gjelder ansatt', isDark),
                    const SizedBox(height: 12),
                    _buildEmployeeSelector(isDark),
                    const SizedBox(height: 20),
                  ],
                  if (widget.type == AbsenceType.egenmelding &&
                      _periodUsage != null) ...[
                    LeaveUsageMeter(
                      title: 'Egenmelding i perioden',
                      used: _periodUsage!.egenmeldingDaysUsed,
                      max: _companySettings.egenmeldingDaysPerYear,
                      subtitle:
                          '${_periodUsage!.window.formatRange()} · maks $maxConsec dager per søknad',
                      icon: Icons.sick_outlined,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.type == AbsenceType.ferie && _quota != null)
                    _buildQuotaInfo(isDark, totalDays),
                  if (widget.type == AbsenceType.syktBarn) ...[
                    LeaveUsageMeter(
                      title: 'Sykt barn i perioden',
                      used: _periodUsage?.syktBarnDaysUsed ?? 0,
                      max: _companySettings.syktBarnDaysLimit(
                        childrenUnder12: _childrenUnder12,
                      ),
                      subtitle: _periodUsage?.window.formatRange(),
                      icon: Icons.child_care_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSyktBarnProfileInfo(isDark),
                  ],
                  _sectionHeader('Periode', isDark),
                  const SizedBox(height: 8),
                  if (widget.type == AbsenceType.egenmelding)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Velg inntil $maxConsec sammenhengende dager.',
                        style: DriftProTheme.caption,
                      ),
                    ),
                  _buildDatePickerCard(isDark, totalDays),
                  if (_overlaps.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DepartmentLeaveTipCard(
                      overlaps: _overlaps,
                      departmentName: _departmentName,
                      isApprovalContext:
                          _directRegister && widget.type == AbsenceType.ferie,
                    ),
                  ],
                  if (_canSeeRules) ...[
                    const SizedBox(height: 20),
                    LeaveRulesPanel(highlightType: widget.type, compact: true),
                  ],
                  const SizedBox(height: 20),
                  _sectionHeader('Kommentar (valgfritt)', isDark),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _commentController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Kort merknad til leder…',
                      fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: (_isSubmitting || _leaderSelfBlocked)
                          ? null
                          : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.primaryGreen,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _submitButtonLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
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

  Widget _buildEgenmeldingBlockedBody(bool isDark) {
    final usage = _periodUsage!;
    final name = _selectedEmployee?.fullName ?? 'Ansatt';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DriftProTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DriftProTheme.warning.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Egenmelding er brukt opp', style: DriftProTheme.headingSm),
                const SizedBox(height: 8),
                Text(
                  _isSelfRequest
                      ? 'Du har brukt opp egenmeldingskvoten i ${usage.window.formatRange()}.'
                      : '$name har brukt opp egenmeldingskvoten i ${usage.window.formatRange()}.',
                  style: DriftProTheme.bodySm,
                ),
                const SizedBox(height: 12),
                Text(
                  '${usage.egenmeldingDaysUsed}/${_companySettings.egenmeldingDaysPerYear} dager · '
                  '${usage.egenmeldingPeriodsUsed}/${LeaveRules.egenmeldingMaxPeriodsPerYear} tilfeller',
                  style: DriftProTheme.labelMd,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Alternativer', style: DriftProTheme.headingSm),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NewAbsenceScreen(
                    type: AbsenceType.sykmelding,
                    allowPickEmployee: widget.allowPickEmployee,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.medical_services_outlined),
            label: const Text('Registrer sykmelding'),
          ),
          const SizedBox(height: 16),
          Text(
            'Leder eller HR kan hjelpe deg når du har sykmelding fra lege.',
            style: DriftProTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildSyktBarnProfileInfo(bool isDark) {
    final count = _childrenUnder12;
    final limit = _companySettings.syktBarnDaysLimit(childrenUnder12: count);
    final used = _periodUsage?.syktBarnDaysUsed ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.absenceSickChild.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DriftProTheme.absenceSickChild.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.child_care_rounded,
                  color: DriftProTheme.absenceSickChild),
              const SizedBox(width: 10),
              Text('Sykt barn-kvote', style: DriftProTheme.labelLg),
            ],
          ),
          const SizedBox(height: 8),
          if (count == 0)
            Text(
              'Ingen barn under 12 registrert på profilen — standardgrense er '
              '${LeaveRules.syktBarnDaysPerChildUnder12} dager. Oppdater under Min profil '
              'hvis du har barn, slik at systemet gir ${LeaveRules.syktBarnDaysTwoOrMoreChildren} dager ved 2+ barn.',
              style: DriftProTheme.bodySm,
            )
          else
            Text(
              '$count barn under 12 registrert → $limit dager i perioden '
              '${_periodUsage?.window.formatRange() ?? ''}. '
              'Brukt: $used/$limit.',
              style: DriftProTheme.bodySm,
            ),
        ],
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
    final byYear = _startDate != null && _endDate != null
        ? BusinessDays.daysByYear(_startDate!, _endDate!)
        : const <int, int>{};
    final yearLines = _quotasByYear.entries.map((e) {
      final q = e.value;
      final remaining = q.vacationDaysRemaining;
      final needed = byYear[e.key] ?? 0;
      final after = remaining - needed;
      return '${e.key}: $remaining igjen'
          '${needed > 0 ? ' (trekker $needed)' : ''}'
          '${needed > 0 && after >= 0 ? ' → $after etterpå' : ''}'
          '${needed > 0 && after < 0 ? ' — mangler ${-after}' : ''}';
    }).join('\n');

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
            'Feriebalanse',
            style: DriftProTheme.labelSm.copyWith(color: DriftProTheme.primaryGreen),
          ),
          const SizedBox(height: 8),
          Text(yearLines, style: DriftProTheme.bodySm),
          if (requestedDays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Perioden er $requestedDays virkedager (helg og røde dager telles ikke).',
                style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w600),
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
                  widget.type == AbsenceType.ferie
                      ? '$totalDays virkedager'
                      : '$totalDays dager',
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
