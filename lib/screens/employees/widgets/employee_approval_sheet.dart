import 'package:flutter/material.dart';

import '../../../core/permissions/access_catalog.dart';
import '../../../core/permissions/access_presets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import 'permission_matrix_editor.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

enum ApprovalMode { auto, custom }

/// Godkjenning av ny ansatt: hurtig (auto) eller tilpasset (avkryssing).
class EmployeeApprovalSheet extends StatefulWidget {
  final UserProfile user;
  final List<Department> departments;
  final Future<void> Function({
    required UserRole role,
    required String? departmentId,
    required Map<String, dynamic> accessSettings,
  }) onApprove;

  const EmployeeApprovalSheet({
    super.key,
    required this.user,
    required this.departments,
    required this.onApprove,
  });

  static Future<bool?> show(
    BuildContext context, {
    required UserProfile user,
    required List<Department> departments,
    required Future<void> Function({
      required UserRole role,
      required String? departmentId,
      required Map<String, dynamic> accessSettings,
    }) onApprove,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EmployeeApprovalSheet(
        user: user,
        departments: departments,
        onApprove: onApprove,
      ),
    );
  }

  @override
  State<EmployeeApprovalSheet> createState() => _EmployeeApprovalSheetState();
}

class _EmployeeApprovalSheetState extends State<EmployeeApprovalSheet> {
  ApprovalMode _mode = ApprovalMode.auto;
  UserRole _role = UserRole.ansatt;
  String? _departmentId;
  Map<String, dynamic> _settings =
      AccessCatalog.normalizeV2(null, UserRole.ansatt);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _departmentId = widget.user.departmentId;
    if (_departmentId == null && widget.departments.length == 1) {
      _departmentId = widget.departments.first.id;
    }
  }

  void _applyRolePreset() {
    setState(() => _settings = AccessCatalog.normalizeV2(null, _role));
  }

  Future<void> _submit() async {
    if (_departmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg avdeling før godkjenning')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onApprove(
        role: _role,
        departmentId: _departmentId,
        accessSettings: _settings,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Godkjenning feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  child: Text(widget.user.initials),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user.fullName, style: DriftProTheme.headingSm),
                      Text(widget.user.email, style: DriftProTheme.caption),
                      if (widget.user.phone != null && widget.user.phone!.isNotEmpty)
                        Text('Tlf: ${widget.user.phone}', style: DriftProTheme.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<ApprovalMode>(
              segments: const [
                ButtonSegment(
                  value: ApprovalMode.auto,
                  label: Text('Hurtig'),
                  icon: Icon(Icons.bolt_outlined, size: 18),
                ),
                ButtonSegment(
                  value: ApprovalMode.custom,
                  label: Text('Tilpasset'),
                  icon: Icon(Icons.tune_outlined, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (_mode == ApprovalMode.auto) ...[
                    Text('Velg rolle', style: DriftProTheme.labelLg),
                    const SizedBox(height: 8),
                    _roleCard(
                      UserRole.ansatt,
                      'Ansatt',
                      'Kun egne data i avvik og fravær/ferie',
                      Icons.person_outline,
                    ),
                    const SizedBox(height: 8),
                    _roleCard(
                      UserRole.leder,
                      'Avdelingsleder',
                      'Ser avdelingens data + godkjenner avvik og fravær',
                      Icons.supervisor_account_outlined,
                    ),
                    const SizedBox(height: 8),
                    _roleCard(
                      UserRole.admin,
                      'Administrator',
                      'Hele bedriften (unntatt superadmin-godkjenning)',
                      Icons.admin_panel_settings_outlined,
                    ),
                  ] else ...[
                    Text('Rolle', style: DriftProTheme.labelLg),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<UserRole>(
                      value: _role,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Systemrolle',
                      ),
                      items: [
                        UserRole.ansatt,
                        UserRole.leder,
                        UserRole.admin,
                      ].map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(AccessPresets.presetTitle(r)),
                          )).toList(),
                      onChanged: (r) {
                        if (r == null) return;
                        setState(() {
                          _role = r;
                          _settings = AccessCatalog.normalizeV2(null, r);
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    PermissionMatrixEditor(
                      settings: _settings,
                      roleForPresets: _role,
                      onChanged: (s) => setState(() => _settings = s),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('Avdeling', style: DriftProTheme.labelLg),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _departmentId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Tilhører avdeling',
                    ),
                    items: widget.departments
                        .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                  if (_mode == ApprovalMode.auto) ...[
                    const SizedBox(height: 16),
                    _summaryBox(),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? SizedBox(width: 24, height: 24, child: DriftProLoadingIndicator(size: 24))
                    : const Text('Godkjenn og gi tilgang'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(UserRole role, String title, String subtitle, IconData icon) {
    final selected = _role == role;
    return InkWell(
      onTap: () {
        setState(() {
          _role = role;
          _applyRolePreset();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? DriftProTheme.primaryGreen : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? DriftProTheme.primaryGreen.withValues(alpha: 0.08)
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? DriftProTheme.primaryGreen : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: DriftProTheme.labelLg),
                  Text(subtitle, style: DriftProTheme.caption),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: DriftProTheme.primaryGreen),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox() {
    final enabled = AccessCatalog.countEnabled(_settings);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AccessPresets.presetTitle(_role),
            style: DriftProTheme.labelLg.copyWith(color: DriftProTheme.primaryGreen),
          ),
          const SizedBox(height: 6),
          Text(
            '$enabled funksjoner/sider aktiveres. Brukeren får ikke se det som er av.',
            style: DriftProTheme.caption,
          ),
        ],
      ),
    );
  }
}
