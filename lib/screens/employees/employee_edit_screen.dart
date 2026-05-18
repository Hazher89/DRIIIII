import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';

/// Rediger all personinfo for ansatt (superadmin / leder med tilgang).
class EmployeeEditScreen extends StatefulWidget {
  final UserProfile employee;
  final List<Department> departments;
  final bool canEditRole;

  const EmployeeEditScreen({
    super.key,
    required this.employee,
    required this.departments,
    this.canEditRole = false,
  });

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _jobTitle;
  late final TextEditingController _employeeNumber;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late UserRole _role;
  String? _departmentId;
  DateTime? _birthDate;
  DateTime? _hireDate;
  bool _safetyRep = false;
  bool _smsOptIn = true;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _name = TextEditingController(text: e.fullName);
    _email = TextEditingController(text: e.email);
    _phone = TextEditingController(text: e.phone ?? '');
    _address = TextEditingController(text: e.address ?? '');
    _jobTitle = TextEditingController(text: e.jobTitle ?? '');
    _employeeNumber = TextEditingController(text: e.employeeNumber ?? '');
    _emergencyName = TextEditingController(text: e.emergencyContactName ?? '');
    _emergencyPhone = TextEditingController(text: e.emergencyContactPhone ?? '');
    _role = e.role;
    _departmentId = e.departmentId;
    _birthDate = e.birthDate;
    _hireDate = e.hireDate;
    _safetyRep = e.isSafetyRepresentative;
    _active = e.isActive;
    _loadSmsOptIn();
  }

  Future<void> _loadSmsOptIn() async {
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select('sms_opt_in')
          .eq('id', widget.employee.id)
          .single();
      if (mounted) {
        setState(() => _smsOptIn = row['sms_opt_in'] as bool? ?? true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _jobTitle.dispose();
    _employeeNumber.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.updateEmployeeProfile(
        widget.employee.id,
        fullName: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        jobTitle: _jobTitle.text.trim(),
        employeeNumber: _employeeNumber.text.trim(),
        emergencyContactName: _emergencyName.text.trim(),
        emergencyContactPhone: _emergencyPhone.text.trim(),
        departmentId: _departmentId,
        role: widget.canEditRole ? _role : null,
        birthDate: _birthDate,
        hireDate: _hireDate,
        isSafetyRepresentative: _safetyRep,
        isActive: _active,
        smsOptIn: _smsOptIn,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _phone.text.trim().isNotEmpty
                  ? 'Lagret. Telefon knyttes til Sveve-varsler (Mavi).'
                  : 'Lagret.',
            ),
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rediger ansatt')),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
          child: _saving
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('LAGRE ALLE ENDRINGER'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Personalia'),
          _field(_name, 'Fullt navn *'),
          _field(_email, 'E-post (kun visning)', readOnly: true),
          _field(_phone, 'Mobiltelefon (Sveve-varsler)',
              keyboard: TextInputType.phone,
              hint: '8 siffer – kobles til Mavi SMS'),
          _field(_address, 'Adresse', maxLines: 2),
          _dateTile('Fødselsdato', _birthDate, (d) => _birthDate = d),
          _section('Arbeid'),
          _field(_jobTitle, 'Stilling / yrkestittel'),
          _field(_employeeNumber, 'Ansattnummer'),
          _dateTile('Ansettelsesdato', _hireDate, (d) => _hireDate = d),
          DropdownButtonFormField<String>(
            value: _departmentId,
            decoration: const InputDecoration(labelText: 'Avdeling'),
            items: widget.departments
                .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                .toList(),
            onChanged: (v) => setState(() => _departmentId = v),
          ),
          if (widget.canEditRole) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Systemrolle'),
              items: UserRole.values
                  .where((r) => r != UserRole.samarbeidspartner)
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
          ],
          SwitchListTile(
            title: const Text('Verneombud'),
            value: _safetyRep,
            onChanged: (v) => setState(() => _safetyRep = v),
          ),
          SwitchListTile(
            title: const Text('Aktiv ansatt'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          _section('Pårørende / nødkontakt'),
          _field(_emergencyName, 'Navn på pårørende'),
          _field(_emergencyPhone, 'Telefon pårørende',
              keyboard: TextInputType.phone),
          _section('Varsler'),
          SwitchListTile(
            title: const Text('SMS til denne ansatte'),
            subtitle: const Text(
              'Fravær godkjent/avvist, avvik m.m. (avhenger av firmainnstillinger)',
            ),
            value: _smsOptIn,
            onChanged: (v) => setState(() => _smsOptIn = v),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: DriftProTheme.headingSm),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
    String? hint,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        readOnly: readOnly,
        maxLines: maxLines,
        keyboardType: keyboard,
        inputFormatters: keyboard == TextInputType.phone
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]'))]
            : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime?> set) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        value != null
            ? '${value.day}.${value.month}.${value.year}'
            : 'Ikke satt',
      ),
      trailing: const Icon(Icons.calendar_today),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1950),
          lastDate: DateTime(2035),
        );
        if (d != null) setState(() => set(d));
      },
    );
  }
}
