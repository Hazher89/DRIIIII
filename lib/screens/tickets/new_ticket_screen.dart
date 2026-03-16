import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';

class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();

  TicketSeverity _severity = TicketSeverity.middels;
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  String? _error;

  String? _assignedToId;
  List<UserProfile> _allProfiles = [];
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final profiles = await SupabaseService.fetchProfiles(companyId: companyId);
        setState(() {
          _allProfiles = profiles;
        });
      }
    } catch (e) {
      debugPrint('Error loading profiles: $e');
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Du må være logget inn for å registrere avvik.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        throw StateError('Fant ikke selskap for brukeren.');
      }

      List<String> imageUrls = [];
      for (var image in _selectedImages) {
        final bytes = await image.readAsBytes();
        final fileName = '${const Uuid().v4()}.jpg';
        final path = 'tickets/$companyId/$fileName';
        final url = await SupabaseService.uploadFile('tickets', path, bytes);
        imageUrls.add(url);
      }

      final ticket = Ticket(
        id: '', 
        companyId: companyId,
        reportedBy: user.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
        severity: _severity,
        isAnonymous: _isAnonymous,
        assignedTo: _assignedToId,
        imageUrls: imageUrls,
        status: TicketStatus.aapen,
      );

      await SupabaseService.createTicket(ticket);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Kunne ikke lagre avvik. Prøv igjen.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.newTicket),
      ),
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ticketTitle,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ticketDescription,
                ),
                maxLines: 4,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ticketCategory,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.severity,
                style: DriftProTheme.labelLg,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TicketSeverity.values.map((s) {
                  final selected = s == _severity;
                  return ChoiceChip(
                    label: Text(s.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _severity = s);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                title: const Text(AppStrings.anonymous),
              ),
              const SizedBox(height: 16),
              const Text('Hvem skal behandle avviket?', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _assignedToId,
                decoration: InputDecoration(
                  hintText: 'Velg person',
                  filled: true,
                  fillColor: isDark ? DriftProTheme.cardDark : Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: _allProfiles.map((p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.fullName),
                )).toList(),
                onChanged: (val) => setState(() => _assignedToId = val),
              ),
              const SizedBox(height: 24),
              const Text('Bilder', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildImagePicker(isDark),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: DriftProTheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(AppStrings.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker(bool isDark) {
    return Column(
      children: [
        if (_selectedImages.isNotEmpty)
          Container(
            height: 100,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Text("Bilde ${index + 1}"), // Simplified for web/pickers if path is not direct
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedImages.removeAt(index)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        InkWell(
          onTap: _pickImages,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3), style: BorderStyle.solid),
            ),
            child: const Column(
              children: [
                Icon(Icons.add_a_photo_outlined, color: Colors.grey, size: 24),
                SizedBox(height: 4),
                Text('Legg til bilder', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

