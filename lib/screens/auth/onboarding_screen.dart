import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';

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
  final _jobTitleController = TextEditingController();
  
  String? _selectedDepartmentId;
  List<Department> _departments = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.fullName;
    _phoneController.text = widget.profile.phone ?? '';
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      // For onboarding, we might not have a companyId yet if it's a totally new user.
      // But usually they belong to a company already or we assign one.
      String? companyId = widget.profile.companyId;
      
      if (companyId == null) {
        // Find first company to assign (demo logic)
        final companies = await SupabaseService.client.from('companies').select('id').limit(1);
        if (companies.isNotEmpty) {
          companyId = companies[0]['id'] as String;
        }
      }

      if (companyId != null) {
        final depts = await SupabaseService.fetchDepartments(companyId: companyId);
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
    
    setState(() => _isSaving = true);
    
    try {
      String? companyId = widget.profile.companyId;
      if (companyId == null && _departments.isNotEmpty) {
        companyId = _departments.first.companyId;
      }

      await SupabaseService.client.from('profiles').update({
        'full_name': _nameController.text,
        'phone': _phoneController.text,
        'address': _addressController.text,
        'job_title': _jobTitleController.text,
        'department_id': _selectedDepartmentId,
        'company_id': companyId,
        'is_onboarded': true,
      }).eq('id', widget.profile.id);

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
          ? const Center(child: CircularProgressIndicator())
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
                          'Vennligst fullfør din profil for å komme i gang.',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 48),
                        
                        _buildField('Fullt navn', _nameController, Icons.person_outline),
                        _buildField('Telefonnummer', _phoneController, Icons.phone_android_outlined, keyboardType: TextInputType.phone),
                        _buildField('Adresse', _addressController, Icons.location_on_outlined),
                        _buildField('Stillingstittel', _jobTitleController, Icons.work_outline),
                        
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
                                : const Text('Fullfør og start', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
}
