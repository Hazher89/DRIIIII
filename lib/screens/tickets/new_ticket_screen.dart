import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';

/// Enkel, rask innrapportering for ansatte (tekst + bilder + alvor).
class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TicketSeverity _severity = TicketSeverity.middels;
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  String? _error;
  String? _category;

  static const _categories = [
    'Helse og sikkerhet',
    'Kvalitet',
    'Miljø',
    'Utstyr / teknisk',
    'Annet',
  ];

  final List<_PickedImage> _images = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickGallery() async {
    final List<XFile> picked = await _picker.pickMultiImage();
    await _addFiles(picked);
  }

  Future<void> _pickCamera() async {
    final XFile? shot =
        await _picker.pickImage(source: ImageSource.camera);
    if (shot != null) await _addFiles([shot]);
  }

  Future<void> _addFiles(List<XFile> files) async {
    for (final f in files) {
      final bytes = await f.readAsBytes();
      setState(() => _images.add(_PickedImage(bytes: bytes, name: f.name)));
    }
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
      final profile = await SupabaseService.fetchCurrentUserProfile();

      List<String> imageUrls = [];
      int failedUploads = 0;
      for (var i = 0; i < _images.length; i++) {
        try {
          final fileName = '${const Uuid().v4()}.jpg';
          final path = '$companyId/${const Uuid().v4()}_$fileName';
          final url = await SupabaseService.uploadFile(
            'tickets',
            path,
            _images[i].bytes,
          );
          imageUrls.add(url);
        } catch (_) {
          failedUploads++;
        }
      }

      final ticket = Ticket(
        id: '',
        companyId: companyId,
        departmentId: profile?.departmentId,
        reportedBy: user.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        severity: _severity,
        isAnonymous: _isAnonymous,
        imageUrls: imageUrls,
        status: TicketStatus.aapen,
      );

      await SupabaseService.createTicket(ticket);
      if (!mounted) return;
      if (failedUploads > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Avvik sendt, men $failedUploads bilde(r) kunne ikke lastes opp. Be admin kjøre storage-policy SQL.',
            ),
          ),
        );
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Kunne ikke lagre avvik: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.emergency_outlined,
                      color: DriftProTheme.primaryGreen),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Kort beskrivelse og gjerne bilde. En leder følger opp i kontrollsenteret.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Hva skjedde?',
                hintText: 'Kort tittel',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Påkrevd' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Beskriv situasjonen',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Påkrevd' : null,
            ),
            const SizedBox(height: 18),
            Text('Kategori', style: DriftProTheme.labelLg),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                final sel = _category == c;
                return FilterChip(
                  label: Text(c),
                  selected: sel,
                  onSelected: (_) => setState(() => _category = sel ? null : c),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Text(AppStrings.severity, style: DriftProTheme.labelLg),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TicketSeverity.values.map((s) {
                final selected = s == _severity;
                return ChoiceChip(
                  label: Text(s.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _severity = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
              title: const Text(AppStrings.anonymous),
              subtitle: const Text(
                'Navnet vises ikke for saksbehandlere i listen.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Text('Bilder', style: DriftProTheme.labelLg),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galleri'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Kamera'),
                  ),
                ),
              ],
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  itemBuilder: (ctx, i) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _images[i].bytes,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _images.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: DriftProTheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send inn avvik'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedImage {
  final Uint8List bytes;
  final String name;

  _PickedImage({required this.bytes, required this.name});
}
