import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/supabase_service.dart';
import '../../core/utils/norwegian_national_id.dart';
import '../../core/permissions/statutory_role_access.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/notification_channel.dart';
import '../../models/user_profile.dart';
import '../profile/widgets/notification_channel_picker.dart';

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
  late final TextEditingController _nationalId;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late UserRole _role;
  String? _departmentId;
  DateTime? _birthDate;
  DateTime? _hireDate;
  bool _safetyRep = false;
  bool _unionRep = false;
  bool _chiefSafety = false;
  bool _amuMember = false;
  bool _smsOptIn = true;
  bool _emailOptIn = true;
  NotificationChannel _notifyChannel = NotificationChannel.both;
  bool _active = true;
  int _childrenUnder12 = 0;
  bool _saving = false;

  /// Unngår setState mens datepicker/dialog er åpen (forårsaker _dependents-feil).
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      setState(fn);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(fn);
    });
  }

  String? get _validDepartmentId {
    if (_departmentId == null) return null;
    final ok = widget.departments.any((d) => d.id == _departmentId);
    return ok ? _departmentId : null;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _verifyAccess();
    _name = TextEditingController(text: e.fullName);
    _email = TextEditingController(text: e.email);
    _phone = TextEditingController(text: e.phone ?? '');
    _address = TextEditingController(text: e.address ?? '');
    _jobTitle = TextEditingController(text: e.jobTitle ?? '');
    _employeeNumber = TextEditingController(text: e.employeeNumber ?? '');
    _nationalId = TextEditingController(
      text: NorwegianNationalId.formatDisplay(e.nationalIdNumber),
    );
    _emergencyName = TextEditingController(text: e.emergencyContactName ?? '');
    _emergencyPhone = TextEditingController(text: e.emergencyContactPhone ?? '');
    _role = e.role;
    _departmentId = e.departmentId;
    _birthDate =
        NorwegianNationalId.birthDateFrom(e.nationalIdNumber) ?? e.birthDate;
    _hireDate = e.hireDate;
    _childrenUnder12 = e.childrenUnder12Count;
    _safetyRep = e.isSafetyRepresentative;
    _unionRep = e.isUnionRepresentative;
    _chiefSafety = e.isChiefSafetyRepresentative;
    _amuMember = e.isAmuMember;
    _active = e.isActive;
    _loadNotifyPrefs();
  }

  Future<void> _verifyAccess() async {
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (!mounted) return;
    if (!SupabaseService.canManageEmployees(me)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kun Tommy, Nico eller Hazher kan redigere ansattprofiler.',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _loadNotifyPrefs() async {
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select('sms_opt_in, email_opt_in, notify_channel_preference')
          .eq('id', widget.employee.id)
          .single();
      if (!mounted) return;
      _safeSetState(() {
        _smsOptIn = row['sms_opt_in'] as bool? ?? true;
        _emailOptIn = row['email_opt_in'] as bool? ?? true;
        _notifyChannel = NotificationChannel.fromDb(
          row['notify_channel_preference'] as String?,
        );
      });
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
    _nationalId.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool _emailChanged() {
    final a = _email.text.trim().toLowerCase();
    final b = widget.employee.email.trim().toLowerCase();
    return a != b;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final me = await SupabaseService.fetchCurrentUserProfile();
    if (!SupabaseService.canManageEmployees(me)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kun Tommy, Nico eller Hazher kan lagre endringer.',
            ),
          ),
        );
      }
      return;
    }
    final newEmail = _email.text.trim().toLowerCase();
    if (_emailChanged()) {
      if (newEmail.isEmpty || !_emailPattern.hasMatch(newEmail)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skriv en gyldig e-postadresse')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      var emailUpdated = false;
      if (_emailChanged()) {
        await SupabaseService.updateEmployeeEmail(
          profileId: widget.employee.id,
          newEmail: newEmail,
        );
        emailUpdated = true;
      }
      final normalizedFnr = NorwegianNationalId.normalize(_nationalId.text);
      if (_nationalId.text.trim().isNotEmpty && normalizedFnr == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fødselsnummer må være 11 siffer')),
        );
        setState(() => _saving = false);
        return;
      }
      final fnrBirth = NorwegianNationalId.birthDateFrom(normalizedFnr);
      await SupabaseService.updateEmployeeProfile(
        widget.employee.id,
        fullName: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        jobTitle: _jobTitle.text.trim(),
        employeeNumber: _employeeNumber.text.trim(),
        nationalIdNumber: _nationalId.text.trim(),
        emergencyContactName: _emergencyName.text.trim(),
        emergencyContactPhone: _emergencyPhone.text.trim(),
        departmentId: _departmentId,
        role: widget.canEditRole ? _role : null,
        birthDate: _birthDate ?? fnrBirth,
        hireDate: _hireDate,
        childrenUnder12Count: _childrenUnder12,
        isSafetyRepresentative: _safetyRep || _chiefSafety,
        isUnionRepresentative: _unionRep,
        isChiefSafetyRepresentative: _chiefSafety,
        isAmuMember: _amuMember,
        isActive: _active,
        smsOptIn: _smsOptIn,
        emailOptIn: _emailOptIn,
        notifyChannelPreference: _notifyChannel.dbValue,
      );
      if (mounted) {
        final parts = <String>['Lagret'];
        if (emailUpdated) {
          parts.add('e-post oppdatert for innlogging og e-postvarsler');
        }
        if (_phone.text.trim().isNotEmpty) {
          parts.add('telefon knyttes til SMS-varsler');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${parts.join('. ')}.')),
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
          _field(
            _email,
            'E-post (innlogging og varsler)',
            keyboard: TextInputType.emailAddress,
            hint: 'brukes til innlogging og e-postvarsler fra MAVI',
          ),
          _field(_phone, 'Mobiltelefon (Sveve-varsler)',
              keyboard: TextInputType.phone,
              hint: '8 siffer – kobles til Mavi SMS'),
          _field(_address, 'Adresse', maxLines: 2),
          _field(
            _nationalId,
            'Fødselsnummer',
            keyboard: TextInputType.number,
            hint: '11 siffer — bursdag settes automatisk',
          ),
          _birthDateTile(),
          _section('Arbeid'),
          _field(_jobTitle, 'Stilling / yrkestittel'),
          _field(_employeeNumber, 'Ansattnummer'),
          _hireDateTile(),
          DropdownButtonFormField<String>(
            value: _validDepartmentId,
            decoration: const InputDecoration(
              labelText: 'Avdeling',
              helperText: 'Ansatt kan flyttes til en annen avdeling her',
            ),
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
          _section('Lovpålagte verv'),
          SwitchListTile(
            title: const Text('Verneombud'),
            subtitle: Text(
              StatutoryRoleAccess.verneombudLawHint,
              style: DriftProTheme.caption,
            ),
            value: _safetyRep || _chiefSafety,
            onChanged: _chiefSafety
                ? null
                : (v) => setState(() => _safetyRep = v),
          ),
          SwitchListTile(
            title: const Text('Hovedverneombud'),
            subtitle: Text(
              StatutoryRoleAccess.hovedverneombudLawHint,
              style: DriftProTheme.caption,
            ),
            value: _chiefSafety,
            onChanged: (v) => setState(() {
              _chiefSafety = v;
              if (v) _safetyRep = true;
            }),
          ),
          SwitchListTile(
            title: const Text('Tillitsvalgt'),
            subtitle: Text(
              StatutoryRoleAccess.tillitsvalgtLawHint,
              style: DriftProTheme.caption,
            ),
            value: _unionRep,
            onChanged: (v) => setState(() => _unionRep = v),
          ),
          SwitchListTile(
            title: const Text('AMU-medlem'),
            subtitle: Text(
              StatutoryRoleAccess.amuLawHint,
              style: DriftProTheme.caption,
            ),
            value: _amuMember,
            onChanged: (v) => setState(() => _amuMember = v),
          ),
          SwitchListTile(
            title: const Text('Aktiv ansatt'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          _section('Familie / fravær'),
          Row(
            children: [
              IconButton.filled(
                onPressed: _childrenUnder12 > 0
                    ? () => setState(() => _childrenUnder12--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 12),
              Text('$_childrenUnder12', style: DriftProTheme.headingMd),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _childrenUnder12 < 12
                    ? () => setState(() => _childrenUnder12++)
                    : null,
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Barn under 12 år (sykt barn: '
                  '${_childrenUnder12 >= 2 ? 15 : 10} dager per periode)',
                  style: DriftProTheme.bodySm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _section('Pårørende / nødkontakt'),
          _field(_emergencyName, 'Navn på pårørende'),
          _field(_emergencyPhone, 'Telefon pårørende',
              keyboard: TextInputType.phone),
          _section('Varsler'),
          SwitchListTile(
            title: const Text('Tillat SMS'),
            value: _smsOptIn,
            onChanged: (v) => setState(() => _smsOptIn = v),
          ),
          SwitchListTile(
            title: const Text('Tillat e-post'),
            value: _emailOptIn,
            onChanged: (v) => setState(() => _emailOptIn = v),
          ),
          const SizedBox(height: 8),
          const Text('Foretrukket kanal (når firma sender begge):'),
          const SizedBox(height: 8),
          NotificationChannelPicker(
            value: _notifyChannel,
            onChanged: (v) => setState(() => _notifyChannel = v),
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

  Widget _birthDateTile() {
    return InkWell(
      onTap: _pickBirthDate,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fødselsdato',
          suffixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(
          _birthDate != null
              ? '${_birthDate!.day}.${_birthDate!.month}.${_birthDate!.year}'
              : 'Velg dato',
          style: TextStyle(
            color: _birthDate != null
                ? Theme.of(context).textTheme.bodyLarge?.color
                : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }

  Widget _hireDateTile() {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Ansettelsesdato'),
      subtitle: Text(
        _hireDate != null
            ? '${_hireDate!.day}.${_hireDate!.month}.${_hireDate!.year}'
            : 'Ikke satt',
      ),
      trailing: const Icon(Icons.calendar_today),
      onTap: _pickHireDate,
    );
  }

  DateTime _clampDate(DateTime date, DateTime min, DateTime max) {
    if (date.isBefore(min)) return min;
    if (date.isAfter(max)) return max;
    return date;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final first = DateTime(1925);
    final last = now;
    final fallback = DateTime(now.year - 30, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      useRootNavigator: true,
      initialDate: _clampDate(_birthDate ?? fallback, first, last),
      firstDate: first,
      lastDate: last,
      helpText: 'Velg fødselsdato',
    );
    if (!mounted || picked == null) return;
    _safeSetState(() => _birthDate = picked);
  }

  Future<void> _pickHireDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate ?? now,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 2),
      helpText: 'Velg ansettelsesdato',
    );
    if (!mounted || picked == null) return;
    _safeSetState(() => _hireDate = picked);
  }
}
