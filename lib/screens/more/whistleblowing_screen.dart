import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/whistleblowing_report.dart';

class WhistleblowingScreen extends StatefulWidget {
  const WhistleblowingScreen({super.key});

  @override
  State<WhistleblowingScreen> createState() => _WhistleblowingScreenState();
}

class _WhistleblowingScreenState extends State<WhistleblowingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw Exception('Kunne ikke finne selskap-ID');

      List<String> imageUrls = [];
      for (var image in _selectedImages) {
        final bytes = await image.readAsBytes();
        final fileName = '${const Uuid().v4()}.jpg';
        final path = 'whistleblowing/$companyId/$fileName';
        final url = await SupabaseService.uploadFile('tickets', path, bytes);
        imageUrls.add(url);
      }

      final report = WhistleblowingReport(
        id: '',
        companyId: companyId,
        title: _titleController.text,
        description: _descriptionController.text,
        imageUrls: imageUrls,
      );

      await SupabaseService.createWhistleblowingReport(report);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Anmeldelse sendt'),
            content: const Text('Din anmeldelse er sendt helt anonymt til superadmin. Takk for at du sier ifra.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context); // back to previous screen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved sending: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Anonym anmeldelse'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security, color: Colors.amber),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Denne anmeldelsen sendes helt anonymt. Verken lederen din eller superadmin vil se hvem som har sendt den.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text('Hva gjelder saken?', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Tittel på saken',
                  filled: true,
                  fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 24),
              const Text('Beskriv saken i detalj', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Skriv her...',
                  filled: true,
                  fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 24),
              const Text('Bilder (valgfritt)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildImagePicker(isDark),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DriftProTheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send anmeldelse anonymt', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
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
                        image: DecorationImage(
                          image: NetworkImage('file://${_selectedImages[index].path}'),
                          fit: BoxFit.cover,
                        ),
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
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3), style: BorderStyle.solid),
            ),
            child: const Column(
              children: [
                Icon(Icons.add_a_photo_outlined, color: Colors.grey, size: 32),
                SizedBox(height: 8),
                Text('Trykk for å legge til bilder', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
