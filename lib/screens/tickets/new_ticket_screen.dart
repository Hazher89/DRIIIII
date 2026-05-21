import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_strings.dart';
import '../../core/services/storage/company_file_storage.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';

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
  bool _loadingHandlers = true;
  String? _error;
  String? _category;
  String? _selectedHandlerId;
  List<UserProfile> _handlers = [];

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
  void initState() {
    super.initState();
    _loadHandlers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadHandlers() async {
    setState(() => _loadingHandlers = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (companyId == null) {
        setState(() {
          _handlers = [];
          _loadingHandlers = false;
        });
        return;
      }
      final handlers = await SupabaseService.fetchTicketHandlersForDepartment(
        companyId: companyId,
        departmentId: profile?.departmentId,
      );
      if (!mounted) return;
      setState(() {
        _handlers = handlers;
        _selectedHandlerId = handlers.length == 1 ? handlers.first.id : null;
        _loadingHandlers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _handlers = [];
        _loadingHandlers = false;
        _error = 'Kunne ikke hente ledere: $e';
      });
    }
  }

  String _handlerLabel(UserProfile p) {
    final role = switch (p.role) {
      UserRole.superadmin => 'Superadmin',
      UserRole.admin => 'Admin',
      UserRole.leder => 'Avdelingsleder',
      _ => p.role.name,
    };
    return '${p.fullName} · $role';
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

    if (_selectedHandlerId == null || _selectedHandlerId!.isEmpty) {
      setState(() => _error = 'Velg leder som skal behandle avviket.');
      return;
    }

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
          final stored = await CompanyFileStorage.upload(
            supabaseBucket: 'tickets',
            storagePath: path,
            bytes: _images[i].bytes,
            category: 'tickets',
            fileName: fileName,
          );
          imageUrls.add(CompanyFileStorage.toStorageReference(stored));
        } catch (_) {
          failedUploads++;
        }
      }

      final ticket = Ticket(
        id: '',
        companyId: companyId,
        departmentId: profile?.departmentId,
        reportedBy: user.id,
        assignedTo: _selectedHandlerId,
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
                      'Velg leder som skal behandle avviket. Superadmin og avdelingsleder kan følge opp i kontrollsenteret.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_loadingHandlers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_handlers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Ingen leder funnet — kontakt HR eller admin.',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedHandlerId,
                decoration: const InputDecoration(
                  labelText: 'Leder som behandler avviket *',
                  border: OutlineInputBorder(),
                ),
                items: _handlers
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(_handlerLabel(p)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedHandlerId = v),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Velg leder' : null,
              ),
            const SizedBox(height: 16),
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
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Kamera'),
                  ),
                ),
              ],
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _images[i].bytes,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(4),
                            ),
                            iconSize: 18,
                            onPressed: () =>
                                setState(() => _images.removeAt(i)),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: DriftProTheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting || _handlers.isEmpty ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send avvik'),
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
