import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Registrer ny intern ansatt (navn + ansattnr. for innlogging).
class CreateEmployeeSheet extends StatefulWidget {
  const CreateEmployeeSheet({
    super.key,
    required this.departments,
    required this.companyId,
    required this.requester,
  });

  final List<Department> departments;
  final String companyId;
  final UserProfile requester;

  static Future<UserProfile?> show(
    BuildContext context, {
    required List<Department> departments,
    required String companyId,
    required UserProfile requester,
  }) {
    return showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CreateEmployeeSheet(
        departments: departments,
        companyId: companyId,
        requester: requester,
      ),
    );
  }

  @override
  State<CreateEmployeeSheet> createState() => _CreateEmployeeSheetState();
}

class _CreateEmployeeSheetState extends State<CreateEmployeeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _employeeNoCtrl = TextEditingController();
  final _jobTitleCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String? _departmentId;
  UserRole _role = UserRole.ansatt;
  bool _saving = false;
  String? _error;

  bool get _isLeaderOnly => widget.requester.role == UserRole.leder;
  bool get _canPickRole =>
      widget.requester.isSuperAdmin ||
      widget.requester.role == UserRole.admin;

  @override
  void initState() {
    super.initState();
    if (_isLeaderOnly) {
      _departmentId = widget.requester.departmentId;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _employeeNoCtrl.dispose();
    _jobTitleCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLeaderOnly &&
        (_departmentId == null ||
            _departmentId != widget.requester.departmentId)) {
      setState(() => _error = 'Leder kan kun legge til i egen avdeling');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final created = await SupabaseService.createEmployeeProfile(
        companyId: widget.companyId,
        fullName: _nameCtrl.text.trim(),
        departmentId: _departmentId,
        jobTitle: _jobTitleCtrl.text.trim().isEmpty
            ? null
            : _jobTitleCtrl.text.trim(),
        role: _canPickRole ? _role : UserRole.ansatt,
      );

      await SupabaseService.updateEmployeeProfile(
        created.id,
        employeeNumber: _employeeNoCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ansatt opprettet'),
          content: Text(
            '${created.fullName} er registrert.\n\n'
            'Innlogging: ansattnummer ${_employeeNoCtrl.text.trim()}\n'
            'Standardpassord: 000000\n\n'
            'Be den ansatte bytte passord etter første innlogging.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text:
                        'Ansattnr: ${_employeeNoCtrl.text.trim()}\nPassord: 000000',
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Kopier innlogging'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ferdig'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final depts = _isLeaderOnly
        ? widget.departments
            .where((d) => d.id == widget.requester.departmentId)
            .toList()
        : widget.departments;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Registrer ny ansatt', style: DriftProTheme.headingMd),
              const SizedBox(height: 6),
              Text(
                'Oppretter bruker med ansattnummer for innlogging. '
                'Standardpassord er 000000.',
                style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Fullt navn *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Navn er påkrevd' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _employeeNoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ansattnummer *',
                  helperText: 'Brukes til innlogging i appen',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ansattnummer er påkrevd'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _jobTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Stilling',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _departmentId,
                decoration: const InputDecoration(
                  labelText: 'Avdeling',
                  border: OutlineInputBorder(),
                ),
                items: [
                  if (!_isLeaderOnly)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Ingen avdeling'),
                    ),
                  ...depts.map(
                    (d) => DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text(d.name),
                    ),
                  ),
                ],
                onChanged: _isLeaderOnly
                    ? null
                    : (v) => setState(() => _departmentId = v),
              ),
              if (_canPickRole) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rolle',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: UserRole.ansatt,
                      child: Text('Ansatt'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.leder,
                      child: Text('Leder'),
                    ),
                    DropdownMenuItem(
                      value: UserRole.admin,
                      child: Text('Admin'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: DriftProTheme.bodySm.copyWith(color: DriftProTheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: DriftProTheme.primaryGreen,
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: DriftProLoadingIndicator(size: 22),
                      )
                    : const Text('Opprett ansatt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
