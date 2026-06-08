import 'package:flutter/material.dart';

import '../../../core/services/dms/dms_password.dart';
import '../../../core/services/dms/dms_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Smart opprettelse av mappe: navn, passord, felles/privat, deling.
class DmsCreateFolderSheet extends StatefulWidget {
  final String companyId;
  final String? parentFolderId;
  final String? parentFolderName;
  final bool defaultSharedMavi;

  const DmsCreateFolderSheet({
    super.key,
    required this.companyId,
    this.parentFolderId,
    this.parentFolderName,
    this.defaultSharedMavi = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String companyId,
    String? parentFolderId,
    String? parentFolderName,
    bool defaultSharedMavi = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DmsCreateFolderSheet(
        companyId: companyId,
        parentFolderId: parentFolderId,
        parentFolderName: parentFolderName,
        defaultSharedMavi: defaultSharedMavi,
      ),
    );
  }

  @override
  State<DmsCreateFolderSheet> createState() => _DmsCreateFolderSheetState();
}

class _DmsCreateFolderSheetState extends State<DmsCreateFolderSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  bool _usePassword = false;
  bool _isPrivate = false;
  late bool _isSharedMavi;
  bool _saving = false;
  List<UserProfile> _users = [];
  List<Department> _depts = [];
  final Set<String> _selectedUsers = {};
  final Set<String> _selectedDepts = {};

  @override
  void initState() {
    super.initState();
    _isSharedMavi = widget.defaultSharedMavi;
    _load();
  }

  Future<void> _load() async {
    final users = await SupabaseService.fetchMaviEmployees(companyId: widget.companyId);
    final depts = await SupabaseService.fetchDepartments(companyId: widget.companyId);
    if (mounted) {
      setState(() {
        _users = users;
        _depts = depts;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    if (_usePassword) {
      if (_password.text.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passord må være minst 4 tegn')),
        );
        return;
      }
      if (_password.text != _passwordConfirm.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passordene er ikke like')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await DmsService.createFolderWithSharing(
        name: name,
        parentId: widget.parentFolderId,
        companyId: widget.companyId,
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        passwordHash: _usePassword ? DmsPassword.hash(_password.text) : null,
        isPrivate: _isPrivate,
        isSharedMavi: _isSharedMavi,
        shareUserIds: _isSharedMavi ? const [] : _selectedUsers.toList(),
        shareDepartmentIds: _isSharedMavi ? const [] : _selectedDepts.toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette mappe: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final parent = widget.parentFolderName;
    final manualShare = !_isSharedMavi;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ny mappe', style: DriftProTheme.headingMd),
                        if (parent != null)
                          Text(
                            'Inne i: $parent',
                            style: DriftProTheme.caption,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Mappenavn *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _desc,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Beskrivelse (valgfritt)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFFE8F5E9),
                      child: SwitchListTile(
                        title: const Text(
                          'Felles',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Alle MAVI-ansatte kan se mappen. Samarbeidspartnere og sjåfører får ikke tilgang.',
                        ),
                        value: _isSharedMavi,
                        activeThumbColor: DriftProTheme.primaryGreen,
                        onChanged: (v) => setState(() {
                          _isSharedMavi = v;
                          if (v) {
                            _isPrivate = false;
                            _selectedUsers.clear();
                            _selectedDepts.clear();
                          }
                        }),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Passordbeskyttet mappe'),
                      subtitle: const Text('Krever passord for å åpne'),
                      value: _usePassword,
                      onChanged: (v) => setState(() => _usePassword = v),
                    ),
                    if (_usePassword) ...[
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Passord',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordConfirm,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Bekreft passord',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Privat mappe'),
                      subtitle: const Text(
                        'Kun deg og de du deler med får tilgang',
                      ),
                      value: _isPrivate,
                      onChanged: _isSharedMavi
                          ? null
                          : (v) => setState(() => _isPrivate = v),
                    ),
                    if (manualShare) ...[
                      const Divider(height: 32),
                      Text('Del med ansatte', style: DriftProTheme.headingSm),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _users.map((u) {
                          final sel = _selectedUsers.contains(u.id);
                          return FilterChip(
                            label: Text(u.fullName),
                            selected: sel,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedUsers.add(u.id);
                                } else {
                                  _selectedUsers.remove(u.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text('Del med avdelinger', style: DriftProTheme.headingSm),
                      const SizedBox(height: 8),
                      ..._depts.map((d) {
                        final sel = _selectedDepts.contains(d.id);
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(d.name),
                          value: sel,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedDepts.add(d.id);
                              } else {
                                _selectedDepts.remove(d.id);
                              }
                            });
                          },
                        );
                      }),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Felles mapper deles automatisk med alle ${_users.length} MAVI-ansatte.',
                          style: DriftProTheme.caption,
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                          : const Icon(Icons.create_new_folder),
                      label: Text(_isSharedMavi ? 'Opprett felles mappe' : 'Opprett mappe'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DriftProTheme.primaryGreen,
                        minimumSize: const Size(double.infinity, 48),
                      ),
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
}
