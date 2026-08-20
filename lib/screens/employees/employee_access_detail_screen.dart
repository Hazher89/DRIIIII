import 'package:flutter/material.dart';

import '../../core/permissions/access_catalog.dart';
import '../../core/permissions/access_presets.dart';
import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import 'employee_edit_screen.dart';
import 'widgets/employee_approval_sheet.dart';
import 'widgets/employee_department_leadership_editor.dart';
import 'widgets/employee_files_panel.dart';
import 'widgets/permission_matrix_editor.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../core/layout/web_layout.dart';

/// Full tilgangskonfigurasjon for én ansatt (superadmin).
class EmployeeAccessDetailScreen extends StatefulWidget {
  final UserProfile employee;
  final List<Department> departments;
  final bool isSuperAdmin;
  final bool canEditProfile;
  final VoidCallback? onSaved;

  const EmployeeAccessDetailScreen({
    super.key,
    required this.employee,
    required this.departments,
    required this.isSuperAdmin,
    this.canEditProfile = false,
    this.onSaved,
  });

  @override
  State<EmployeeAccessDetailScreen> createState() =>
      _EmployeeAccessDetailScreenState();
}

class _EmployeeAccessDetailScreenState extends State<EmployeeAccessDetailScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  UserProfile? _currentUser;
  late UserRole _role;
  late String? _departmentId;
  late bool _approved;
  late Map<String, dynamic> _settings;
  bool _saving = false;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initTabs();
    _loadCurrentUser();
    _role = widget.employee.role;
    _departmentId = widget.employee.departmentId;
    _approved = widget.employee.isApproved;
    _settings = AccessCatalog.normalizeV2(widget.employee.accessSettings, _role);
  }

  Future<void> _loadCurrentUser() async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() => _currentUser = me);
  }

  void _initTabs() {
    _tabs?.dispose();
    if (widget.isSuperAdmin || widget.canEditProfile) {
      _tabs = TabController(length: 2, vsync: this);
    } else {
      _tabs = null;
    }
  }

  String get _deptName {
    for (final d in widget.departments) {
      if (d.id == _departmentId) return d.name;
    }
    return 'Ikke valgt';
  }

  void _applyPreset(UserRole role) {
    setState(() {
      _role = role;
      _settings = Map<String, dynamic>.from(AccessPresets.forRoleV2(role));
    });
  }

  Future<void> _save() async {
    if (!widget.isSuperAdmin) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.updateEmployeeAccess(
        profileId: widget.employee.id,
        role: _role,
        departmentId: _departmentId,
        accessSettings: _settings,
        isApproved: _approved,
        setDepartmentLeader: _role == UserRole.leder,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tilganger lagret')),
        );
        widget.onSaved?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEmployee() async {
    if (!widget.isSuperAdmin) return;
    final e = widget.employee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett ansatt permanent?'),
        content: Text(
          '«${e.fullName}» fjernes fra auth og hele systemet. '
          'Handlingen kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett permanent'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.deleteUserPermanently(e.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.fullName} ble slettet')),
        );
        widget.onSaved?.call();
        Navigator.pop(context, true);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sletting feilet: $err'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approve() async {
    final ok = await EmployeeApprovalSheet.show(
      context,
      user: widget.employee,
      departments: widget.departments,
      onApprove: ({required role, required departmentId, required accessSettings}) =>
          SupabaseService.approveEmployee(
        profileId: widget.employee.id,
        role: role,
        departmentId: departmentId,
        accessSettings: accessSettings,
        setDepartmentLeader: role == UserRole.leder,
      ),
    );
    if (ok == true && mounted) {
      widget.onSaved?.call();
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final e = widget.employee;

    if (!widget.isSuperAdmin && !widget.canEditProfile) {
      return Scaffold(
        appBar: AppBar(title: Text(e.fullName)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Du har ikke tilgang til å redigere ansatte.\n'
              'Kontakt superadmin eller avdelingsleder.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(e.fullName),
        bottom: _tabs != null
            ? TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Tilgang'),
                  Tab(text: 'Filer'),
                ],
              )
            : null,
        actions: [
          if (widget.isSuperAdmin &&
              widget.employee.id != _currentUser?.id &&
              widget.employee.role != UserRole.superadmin)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Slett ansatt permanent',
              onPressed: _deleteEmployee,
            ),
          if (widget.canEditProfile || widget.isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Rediger personinfo',
              onPressed: () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmployeeEditScreen(
                      employee: e,
                      departments: widget.departments,
                      canEditRole: widget.isSuperAdmin,
                    ),
                  ),
                );
                if (ok == true) widget.onSaved?.call();
              },
            ),
          if (!e.isApproved)
            TextButton(
              onPressed: _approve,
              child: const Text('Godkjenn'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _tabs != null
                ? DriftProTabView(
                    controller: _tabs,
                    children: [
                      _accessTab(e, isDark),
                      _filesTab(),
                    ],
                  )
                : _accessTab(e, isDark),
          ),
          if (widget.isSuperAdmin) _bottomBar(isDark),
        ],
      ),
    );
  }

  Widget _filesTab() {
    final me = _currentUser;
    if (me == null) {
      return const DriftProLoadingCenter();
    }
    return EmployeeFilesPanel(
      employee: widget.employee,
      currentUser: me,
      canUpload: widget.isSuperAdmin || widget.canEditProfile,
      canManageVisibility: widget.isSuperAdmin,
    );
  }

  Widget _accessTab(UserProfile e, bool isDark) {
    return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _headerCard(e, isDark),
                const SizedBox(height: 16),
                if (!widget.isSuperAdmin) ...[
                  Text(
                    'Som avdelingsleder kan du endre navn, adresse, telefon og pårørende. '
                    'Tilganger til sider endres kun av superadmin.',
                    style: DriftProTheme.caption,
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.isSuperAdmin) ...[
                Text('Rolle & avdeling', style: DriftProTheme.headingSm),
                const SizedBox(height: 8),
                _rolePresets(),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: _role,
                  decoration: const InputDecoration(
                    labelText: 'Systemrolle',
                    border: OutlineInputBorder(),
                  ),
                  items: UserRole.values
                      .where((r) => r != UserRole.samarbeidspartner)
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(AccessPresets.presetTitle(r)),
                          ))
                      .toList(),
                  onChanged: (r) {
                    if (r != null) _applyPreset(r);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _departmentId,
                  decoration: const InputDecoration(
                    labelText: 'Avdeling',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.departments
                      .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                      .toList(),
                  onChanged: (v) async {
                    setState(() => _departmentId = v);
                    if (v != widget.employee.departmentId) {
                      await SupabaseService.updateProfileDepartment(
                        widget.employee.id,
                        v,
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                EmployeeDepartmentLeadershipEditor(
                  employee: widget.employee,
                  departments: widget.departments,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Godkjent – kan logge inn'),
                  subtitle: const Text('Uten dette ser brukeren kun «venter på godkjenning»'),
                  value: _approved,
                  onChanged: (v) => setState(() => _approved = v),
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Alle sider og funksjoner i DriftPro',
                        style: DriftProTheme.headingSm,
                      ),
                    ),
                    Text(
                      '${AccessCatalog.countEnabled(_settings)} aktive',
                      style: DriftProTheme.caption.copyWith(
                        color: DriftProTheme.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PermissionMatrixEditor(
                  settings: _settings,
                  roleForPresets: _role,
                  onChanged: (s) => setState(() => _settings = s),
                ),
                ],
                const SizedBox(height: 80),
              ],
            );
  }

  Widget _headerCard(UserProfile e, bool isDark) {
    final access = UserAccess(e);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            child: Text(e.initials, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.fullName, style: DriftProTheme.headingSm),
                if (e.employeeNumber != null && e.employeeNumber!.isNotEmpty)
                  Text(
                    'Ansattnr. ${e.employeeNumber} (innlogging)',
                    style: DriftProTheme.caption.copyWith(
                      color: DriftProTheme.primaryGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(e.email, style: DriftProTheme.caption),
                if (e.phone != null && e.phone!.isNotEmpty)
                  Text('Tlf (Sveve): ${e.phone}', style: DriftProTheme.caption),
                if (e.address != null && e.address!.isNotEmpty)
                  Text(e.address!, style: DriftProTheme.caption),
                if (e.emergencyContactName != null)
                  Text(
                    'Pårørende: ${e.emergencyContactName}${e.emergencyContactPhone != null ? " (${e.emergencyContactPhone})" : ""}',
                    style: DriftProTheme.caption,
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(_role.name, DriftProTheme.primaryGreen),
                    _chip(_deptName, Colors.blue),
                    _chip(
                      _approved ? 'Godkjent' : 'Venter',
                      _approved ? Colors.green : Colors.orange,
                    ),
                    _chip(
                      '${AccessCatalog.countEnabled(access.toSettingsMap())} tilganger',
                      Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 10, color: color)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }

  Widget _rolePresets() {
    return Wrap(
      spacing: 8,
      children: [
        _presetChip(UserRole.ansatt, 'Ansatt'),
        _presetChip(UserRole.leder, 'Avdelingsleder'),
        _presetChip(UserRole.admin, 'Admin'),
        _presetChip(UserRole.superadmin, 'Superadmin'),
      ],
    );
  }

  Widget _presetChip(UserRole role, String label) {
    final selected = _role == role;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _applyPreset(role),
      selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
    );
  }

  Widget _bottomBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: DriftProTheme.primaryGreen,
          ),
          child: _saving
              ? SizedBox(width: 24, height: 24, child: DriftProLoadingIndicator(size: 24))
              : const Text('Lagre alle tilganger'),
        ),
      ),
    );
  }
}
