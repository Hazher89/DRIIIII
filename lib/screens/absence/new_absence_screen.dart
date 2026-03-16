import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_icons.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';

class NewAbsenceScreen extends StatefulWidget {
  final AbsenceType type;

  const NewAbsenceScreen({super.key, required this.type});

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
  List<UserProfile> _departmentEmployees = [];
  UserProfile? _selectedEmployee;
  
  AbsenceQuota? _quota;
  List<Absence> _potentialConflicts = [];
  bool _isLoadingContext = true;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    setState(() => _isLoadingContext = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile != null) {
        _profile = profile;
        _selectedEmployee = profile;
        
        // If leader/admin, fetch all employees to allow registering for them
        if (profile.isLeader || profile.isAdmin) {
          _departmentEmployees = await SupabaseService.fetchProfiles(
            companyId: profile.companyId,
            departmentId: profile.departmentId,
          );
        }

        await _loadQuotaForSelected();
      }
    } finally {
      if (mounted) setState(() => _isLoadingContext = false);
    }
  }

  Future<void> _loadQuotaForSelected() async {
    if (_selectedEmployee == null) return;
    final quota = await SupabaseService.fetchAbsenceQuota(userId: _selectedEmployee!.id);
    setState(() => _quota = quota);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _checkConflicts() async {
    if (_startDate == null || _endDate == null || _selectedEmployee?.departmentId == null) return;

    final absences = await SupabaseService.fetchAbsences(
      departmentId: _selectedEmployee!.departmentId,
    );

    final conflicts = absences.where((a) {
      if (a.userId == _selectedEmployee!.id) return false;
      if (a.status == AbsenceStatus.avvist) return false;
      return !(_endDate!.isBefore(a.startDate) || _startDate!.isAfter(a.endDate));
    }).toList();

    setState(() {
      _potentialConflicts = conflicts;
    });
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
      _checkConflicts();
    }
  }

  Future<void> _submit() async {
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Velg tidsperiode.');
      return;
    }

    if (_selectedEmployee == null || _profile == null) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final absence = Absence(
        id: 'temp',
        userId: _selectedEmployee!.id,
        companyId: _profile!.companyId!,
        departmentId: _selectedEmployee!.departmentId,
        type: widget.type,
        startDate: _startDate!,
        endDate: _endDate!,
        status: (_profile?.id == _selectedEmployee?.id) ? AbsenceStatus.ventende : AbsenceStatus.godkjent,
        comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      );

      await SupabaseService.createAbsence(absence);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Kunne ikke lagre fravær: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalDays = _startDate != null && _endDate != null
        ? _endDate!.difference(_startDate!).inDays + 1
        : 0;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
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
                // Employee Selector (only for leaders)
                if (_profile?.isLeader == true || _profile?.isAdmin == true) ...[
                  _buildSectionHeader('Gjelder ansatt', isDark),
                  const SizedBox(height: 12),
                  _buildEmployeeSelector(isDark),
                  const SizedBox(height: 24),
                ],

                // Quota Info Card
                if (widget.type == AbsenceType.ferie && _quota != null)
                  _buildQuotaInfo(isDark),

                const SizedBox(height: 24),
                
                // Date Picker Card
                _buildSectionHeader('Tidsperiode', isDark),
                const SizedBox(height: 12),
                _buildDatePickerCard(isDark, totalDays),

                const SizedBox(height: 24),

                // Conflict Warning
                if (_potentialConflicts.isNotEmpty)
                  _buildConflictWarning(isDark),

                const SizedBox(height: 24),

                // Norwegian Law Tip
                _buildLegalTip(isDark),

                const SizedBox(height: 24),

                // Comment
                _buildSectionHeader('Kommentar (valgfritt)', isDark),
                const SizedBox(height: 12),
                TextField(
                  controller: _commentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Legg til utfyllende informasjon...',
                    fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
                ],

                const SizedBox(height: 40),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text((_selectedEmployee?.id == _profile?.id) ? 'Send søknad'.toUpperCase() : 'Registrer fravær'.toUpperCase(), 
                            style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 40),
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
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserProfile>(
          isExpanded: true,
          value: _selectedEmployee,
          items: _departmentEmployees.map((e) => DropdownMenuItem(
            value: e,
            child: Text(e.id == _profile?.id ? 'Meg selv (${e.fullName})' : e.fullName),
          )).toList(),
          onChanged: (val) {
            setState(() => _selectedEmployee = val);
            _loadQuotaForSelected();
            _checkConflicts();
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title.toUpperCase(),
      style: DriftProTheme.labelSm.copyWith(
        color: isDark ? Colors.grey[500] : Colors.grey[600],
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildQuotaInfo(bool isDark) {
    final remaining = _quota!.vacationDaysRemaining;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriftProTheme.primaryGreen.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feriekvote for ${DateTime.now().year} (${_selectedEmployee?.fullName})',
                  style: DriftProTheme.labelSm.copyWith(color: DriftProTheme.primaryGreen),
                ),
                Text(
                  'Gjenstående dager: $remaining',
                  style: DriftProTheme.bodyMd.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
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
          border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
          boxShadow: DriftProTheme.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Fra - Til', style: DriftProTheme.caption),
                   const SizedBox(height: 4),
                   Text(
                     _startDate != null && _endDate != null
                       ? '${_startDate!.day}. ${_getMonth(_startDate!.month)} - ${_endDate!.day}. ${_getMonth(_endDate!.month)}'
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.calendar_today_rounded, color: DriftProTheme.primaryGreen.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictWarning(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DriftProTheme.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DriftProTheme.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: DriftProTheme.warning),
              const SizedBox(width: 12),
              Text(
                'Mulig overlapping (krasj)',
                style: DriftProTheme.labelLg.copyWith(color: DriftProTheme.warning),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Det er ${_potentialConflicts.length} andre kollegaer i avdelingen som har registrert fravær i denne perioden.',
            style: DriftProTheme.bodySm,
          ),
        ],
      ),
    );
  }

  Widget _buildLegalTip(bool isDark) {
    String tipTitle;
    String tipText;

    if (widget.type == AbsenceType.ferie) {
      tipTitle = 'Lovdata: Ferieloven';
      tipText = 'Arbeidstaker har rett på 25 virkedager ferie hvert år. Du kan kreve at hovedferie (18 dager) gis i tiden 1. juni til 30. september.';
    } else if (widget.type == AbsenceType.egenmelding) {
      tipTitle = 'Lovdata: Folketrygdloven';
      tipText = 'Egenmelding kan brukes i opptil 3 kalenderdager om gangen. For lengre fravær kreves sykmelding fra lege.';
    } else {
      tipTitle = 'HMS Tips';
      tipText = 'Husk å registrere alle avvik og fravær tidlig for å sikre god ressursplanlegging i din avdeling.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.blueGrey.withOpacity(0.1) : Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.blueGrey.withOpacity(0.2) : Colors.blue.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tipTitle, style: DriftProTheme.labelSm.copyWith(color: Colors.blue[800])),
          const SizedBox(height: 8),
          Text(tipText, style: DriftProTheme.bodySm.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  String _getMonth(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Des'];
    return names[m - 1];
  }
}
