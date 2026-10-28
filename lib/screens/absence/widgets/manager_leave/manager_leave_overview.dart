import 'package:flutter/material.dart';

import '../../../../core/config/driftpro_client.dart';
import '../../../../core/constants/leave_rules.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/absence.dart';
import '../../../../models/user_profile.dart';
import '../absence_excel_export_sheet.dart';
import '../leave_period_scope.dart';
import 'manager_leave_approvals_panel.dart';
import 'manager_leave_helpers.dart';
import 'manager_leave_insights.dart';
import 'manager_leave_roster_table.dart';

/// Moderne lederoversikt for Fravær & Ferie — uten faner og uten årskalender.
class ManagerLeaveOverview extends StatefulWidget {
  const ManagerLeaveOverview({
    super.key,
    required this.teamProfiles,
    required this.scopedAbsences,
    required this.pendingApprovals,
    required this.teamQuotas,
    required this.departmentNames,
    required this.leaderProfile,
    required this.selectedYear,
    required this.onRefresh,
    required this.onRegister,
    required this.onApprove,
    required this.onReject,
    required this.onOpenAbsence,
    required this.onOpenEmployee,
    this.onYearChanged,
    this.onOpenMine,
    this.onOpenVacationAdmin,
    this.companySettings = const CompanyLeaveSettings(),
    this.approverNames = const {},
    this.companyName,
    this.isLoading = false,
  });

  final List<UserProfile> teamProfiles;
  final List<Absence> scopedAbsences;
  final List<Absence> pendingApprovals;
  final List<AbsenceQuota> teamQuotas;
  final Map<String, String> departmentNames;
  final UserProfile? leaderProfile;
  final int selectedYear;
  final Future<void> Function() onRefresh;
  final VoidCallback onRegister;
  final Future<void> Function(Absence absence) onApprove;
  final Future<void> Function(Absence absence, {String? decisionComment})
      onReject;
  final void Function(Absence absence) onOpenAbsence;
  final void Function(UserProfile employee) onOpenEmployee;
  final ValueChanged<int>? onYearChanged;
  final VoidCallback? onOpenMine;
  final VoidCallback? onOpenVacationAdmin;
  final CompanyLeaveSettings companySettings;
  final Map<String, String> approverNames;
  final String? companyName;
  final bool isLoading;

  @override
  State<ManagerLeaveOverview> createState() => _ManagerLeaveOverviewState();
}

class _ManagerLeaveOverviewState extends State<ManagerLeaveOverview> {
  final _scrollCtrl = ScrollController();
  final _approvalsKey = GlobalKey();
  String? _departmentId;
  String? _employeeId;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _scrollToApprovals() async {
    final ctx = _approvalsKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _rejectWithComment(Absence absence) async {
    final commentCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Avslå søknad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Avslå ${absence.type.label.toLowerCase()} for '
                '${absence.userName ?? 'ansatt'}?',
                style: DriftProTheme.bodySm,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Kommentar til ansatt (valgfritt)',
                  hintText: 'F.eks. overlapper med bemanningsbehov…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, commentCtrl.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.error,
              ),
              child: const Text('Avslå'),
            ),
          ],
        );
      },
    );
    commentCtrl.dispose();
    if (result == null) return;
    await widget.onReject(
      absence,
      decisionComment: result.isEmpty ? null : result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allEmployees = ManagerLeaveHelpers.employeesInScope(
      teamProfiles: widget.teamProfiles,
      leader: widget.leaderProfile,
    );
    var scopedEmployees = allEmployees;
    if (_departmentId != null) {
      scopedEmployees =
          scopedEmployees.where((e) => e.departmentId == _departmentId).toList();
    }
    if (_employeeId != null) {
      scopedEmployees =
          scopedEmployees.where((e) => e.id == _employeeId).toList();
    }
    final scopedIds = scopedEmployees.map((e) => e.id).toSet();
    final scopedAbsences = widget.scopedAbsences
        .where((a) => scopedIds.contains(a.userId))
        .toList();

    final pending = List<Absence>.from(widget.pendingApprovals)
        .where((a) => scopedIds.contains(a.userId))
        .toList()
      ..sort((a, b) {
        final ac = a.createdAt ?? a.startDate;
        final bc = b.createdAt ?? b.startDate;
        return bc.compareTo(ac);
      });

    final awayToday = scopedAbsences
        .where(ManagerLeaveHelpers.isApprovedActiveToday)
        .toList()
      ..sort((a, b) => (a.userName ?? '').compareTo(b.userName ?? ''));

    final nextWeek = ManagerLeaveHelpers.absencesNextWeek(scopedAbsences);
    final nextWeekUsers = ManagerLeaveHelpers.uniqueUsers(nextWeek).length;

    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF8FAFC);

    if (widget.isLoading && allEmployees.isEmpty && pending.isEmpty) {
      return ColoredBox(
        color: bg,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ColoredBox(
      color: bg,
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  DriftProClient.isMobile ? 8 : 16,
                  16,
                  8,
                ),
                child: _PageHeader(
                  onRegister: widget.onRegister,
                  onOpenMine: widget.onOpenMine,
                  onOpenVacationAdmin: widget.onOpenVacationAdmin,
                  onRefresh: widget.onRefresh,
                  onExportExcel: () => showAbsenceExcelExportSheet(
                    context,
                    employees: widget.teamProfiles,
                    absences: widget.scopedAbsences,
                    quotas: widget.teamQuotas,
                    departmentNames: widget.departmentNames,
                    approverNames: widget.approverNames,
                    initialScope: LeavePeriodScope.year(widget.selectedYear),
                    company: widget.companySettings,
                    companyName: widget.companyName,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: ManagerLeaveScopeFilters(
                  employees: allEmployees,
                  departmentNames: widget.departmentNames,
                  departmentId: _departmentId,
                  employeeId: _employeeId,
                  onDepartmentChanged: (id) => setState(() {
                    _departmentId = id;
                    if (_employeeId != null &&
                        !allEmployees.any((e) =>
                            e.id == _employeeId &&
                            (id == null || e.departmentId == id))) {
                      _employeeId = null;
                    }
                  }),
                  onEmployeeChanged: (id) => setState(() => _employeeId = id),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: ManagerLeaveInsights(
                  employees: scopedEmployees,
                  absences: scopedAbsences,
                  quotas: widget.teamQuotas,
                  year: widget.selectedYear,
                  pendingCount: pending.length,
                  awayToday: awayToday,
                  nextWeekAwayCount: nextWeekUsers,
                  onScrollToApprovals: _scrollToApprovals,
                  onOpenEmployee: widget.onOpenEmployee,
                ),
              ),
            ),
            if (pending.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: KeyedSubtree(
                    key: _approvalsKey,
                    child: ManagerLeaveApprovalsPanel(
                      pending: pending,
                      onApprove: widget.onApprove,
                      onReject: _rejectWithComment,
                      onOpen: widget.onOpenAbsence,
                    ),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: SizedBox(key: _approvalsKey, height: 0),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  DriftProClient.isMobile ? 100 : 32,
                ),
                child: ManagerLeaveRosterTable(
                  employees: scopedEmployees,
                  absences: scopedAbsences,
                  quotas: widget.teamQuotas,
                  departmentNames: widget.departmentNames,
                  year: widget.selectedYear,
                  onOpenEmployee: widget.onOpenEmployee,
                  onYearChanged: widget.onYearChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.onRegister,
    required this.onRefresh,
    this.onOpenMine,
    this.onOpenVacationAdmin,
    this.onExportExcel,
  });

  final VoidCallback onRegister;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenMine;
  final VoidCallback? onOpenVacationAdmin;
  final VoidCallback? onExportExcel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final narrow = MediaQuery.sizeOf(context).width < 640;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fravær & Ferie',
          style: DriftProTheme.headingMd.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: narrow ? 24 : 28,
            letterSpacing: -0.4,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Godkjenn søknader, se bemanning og følg feriesaldo.',
          style: DriftProTheme.bodySm.copyWith(
            color: isDark ? Colors.white60 : const Color(0xFF64748B),
          ),
        ),
      ],
    );

    final primary = FilledButton.icon(
      onPressed: onRegister,
      icon: const Icon(Icons.add_rounded, size: 20),
      label: Text(narrow ? 'Registrer' : 'Registrer fravær/ferie'),
      style: FilledButton.styleFrom(
        backgroundColor: DriftProTheme.primaryGreen,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: narrow ? 14 : 18,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );

    final more = PopupMenuButton<String>(
      tooltip: 'Flere valg',
      onSelected: (v) {
        switch (v) {
          case 'mine':
            onOpenMine?.call();
          case 'admin':
            onOpenVacationAdmin?.call();
          case 'export':
            onExportExcel?.call();
          case 'refresh':
            onRefresh();
        }
      },
      itemBuilder: (_) => [
        if (onOpenMine != null)
          const PopupMenuItem(
            value: 'mine',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_outline),
              title: Text('Mine søknader'),
            ),
          ),
        if (onExportExcel != null)
          const PopupMenuItem(
            value: 'export',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.file_download_outlined),
              title: Text('Eksporter Excel'),
            ),
          ),
        if (onOpenVacationAdmin != null)
          const PopupMenuItem(
            value: 'admin',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('Ferieadministrasjon'),
            ),
          ),
        const PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.refresh),
            title: Text('Oppdater'),
          ),
        ),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: primary),
              const SizedBox(width: 4),
              more,
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        primary,
        const SizedBox(width: 4),
        more,
      ],
    );
  }
}
