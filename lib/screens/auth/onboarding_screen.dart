import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class OnboardingScreen extends StatefulWidget {
  final UserProfile profile;
  const OnboardingScreen({super.key, required this.profile});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  DateTime? _birthDate;
  
  String? _selectedDepartmentId;
  String? _resolvedCompanyId;
  List<Department> _departments = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.fullName;
    _phoneController.text = widget.profile.phone ?? '';
    _addressController.text = widget.profile.address ?? '';
    _emergencyNameController.text = widget.profile.emergencyContactName ?? '';
    _emergencyPhoneController.text = widget.profile.emergencyContactPhone ?? '';
    _birthDate = widget.profile.birthDate;
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      // Sikre company-kontekst for nye OAuth-brukere før vi henter avdelinger.
      String? companyId = widget.profile.companyId;

      if (companyId == null) {
        final companies = await SupabaseService.client.from('companies').select('id').limit(1);
        if (companies.isNotEmpty) {
          companyId = companies[0]['id'] as String;
          await SupabaseService.client
              .from('profiles')
              .update({'company_id': companyId})
              .eq('id', widget.profile.id);
        }
      }
      _resolvedCompanyId = companyId;

      if (companyId != null) {
        var depts = await SupabaseService.fetchDepartments(companyId: companyId);
        // Fallback: hvis company peker til "feil" tenant uten avdelinger, hent bootstrap-id.
        if (depts.isEmpty) {
          final bootstrap = await SupabaseService.discoverBootstrapCompanyId();
          if (bootstrap != null && bootstrap != companyId) {
            companyId = bootstrap;
            await SupabaseService.client
                .from('profiles')
                .update({'company_id': companyId})
                .eq('id', widget.profile.id);
            depts = await SupabaseService.fetchDepartments(companyId: companyId);
          }
        }
        _resolvedCompanyId = companyId;
        setState(() {
          _departments = depts;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveOnboarding() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vennligst velg fødselsdato')),
      );
      return;
    }
    
    setState(() => _isSaving = true);
    
    try {
      String? companyId = _resolvedCompanyId ?? widget.profile.companyId;
      if (companyId == null && _departments.isNotEmpty) {
        companyId = _departments.first.companyId;
      }

      final updates = <String, dynamic>{
        'full_name': _nameController.text,
        'phone': _phoneController.text,
        'address': _addressController.text,
        'birth_date': _birthDate?.toIso8601String().split('T').first,
        'emergency_contact_name': _emergencyNameController.text,
        'emergency_contact_phone': _emergencyPhoneController.text,
        'department_id': _selectedDepartmentId,
        'company_id': companyId,
        'is_onboarded': true,
      };
      await SupabaseService.client
          .from('profiles')
          .update(updates)
          .eq('id', widget.profile.id);

      if (mounted) {
        // Trigger a refresh of the app state
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved lagring: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      body: SafeArea(
        child: _isLoading 
          ? const DriftProLoadingCenter()
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Velkommen til DriftPro!',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Fyll ut skjemaet. Telefonnummer brukes til SMS-varsler. '
                          'Etterpå får du standard ansatt-tilgang i appen.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 48),
                        
                        _buildField('Fullt navn', _nameController, Icons.person_outline),
                        _buildField(
                          'Telefonnummer (påkrevd for varsler)',
                          _phoneController,
                          Icons.phone_android_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        _buildField('Adresse', _addressController, Icons.location_on_outlined),
                        _buildBirthDateField(),
                        _buildField('Pårørende - navn', _emergencyNameController, Icons.family_restroom_outlined),
                        _buildField('Pårørende - telefon', _emergencyPhoneController, Icons.contact_phone_outlined, keyboardType: TextInputType.phone),
                        
                        const Text('Avdeling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedDepartmentId,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            prefixIcon: const Icon(Icons.business_outlined),
                          ),
                          hint: const Text('Velg din avdeling'),
                          items: _departments.map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name),
                          )).toList(),
                          onChanged: (val) => setState(() => _selectedDepartmentId = val),
                          validator: (val) => val == null ? 'Vennligst velg en avdeling' : null,
                        ),
                        if (_departments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Fant ingen avdelinger ennå. Trykk "Oppdater" eller kontakt admin.',
                              style: TextStyle(color: Colors.orange[700], fontSize: 12),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _loadDepartments,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Oppdater avdelinger'),
                          ),
                        ),
                        
                        const SizedBox(height: 48),
                        
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveOnboarding,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DriftProTheme.primaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Send inn til godkjenning', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
            prefixIcon: Icon(icon, color: DriftProTheme.primaryGreen),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: (val) => val == null || val.isEmpty ? 'Må fylles ut' : null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBirthDateField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateText = _birthDate == null
        ? 'Velg fødselsdato'
        : '${_birthDate!.day.toString().padLeft(2, '0')}.${_birthDate!.month.toString().padLeft(2, '0')}.${_birthDate!.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Fødselsdato', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _birthDate ?? DateTime(now.year - 30, 1, 1),
              firstDate: DateTime(1900),
              lastDate: now,
            );
            if (picked != null) setState(() => _birthDate = picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
              prefixIcon: const Icon(Icons.cake_outlined, color: DriftProTheme.primaryGreen),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            child: Text(dateText),
          ),
        ),
        if (_birthDate == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Fødselsdato må fylles ut', style: TextStyle(fontSize: 12, color: Colors.red)),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
