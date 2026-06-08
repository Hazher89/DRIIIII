import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/hms/hms_ecosystem_service.dart';
import '../../models/hms/hms_ticket_template.dart';
import '../../models/ticket.dart';
import '../../models/ticket_assignee_options.dart';
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
  TicketAssigneeOptions _assignees = const TicketAssigneeOptions();
  List<HmsTicketTemplate> _templates = [];
  bool _capturingGps = false;
  double? _gpsLat;
  double? _gpsLng;
  HmsDomain _domain = HmsDomain.hms;
  bool _hasPersonalInjury = false;

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
    _loadTemplates();
    _captureGps();
  }

  Future<void> _loadTemplates() async {
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      final templates =
          await HmsEcosystemService.fetchTicketTemplates(companyId: companyId);
      if (mounted) setState(() => _templates = templates);
    } catch (_) {}
  }

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (mounted) {
        setState(() {
          _gpsLat = pos.latitude;
          _gpsLng = pos.longitude;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _capturingGps = false);
    }
  }

  void _applyTemplate(HmsTicketTemplate t) {
    setState(() {
      _titleController.text = t.title;
      _descriptionController.text = t.descriptionTemplate;
      _category = t.category;
      _severity = TicketSeverity.fromDb(t.severityDb);
      _domain = t.domain;
    });
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
          _assignees = const TicketAssigneeOptions();
          _loadingHandlers = false;
        });
        return;
      }
      final options = await SupabaseService.fetchTicketAssigneeOptions(
        companyId: companyId,
        departmentId: profile?.departmentId,
      );
      if (!mounted) return;
      setState(() {
        _assignees = options;
        _selectedHandlerId = options.defaultAssigneeId;
        _loadingHandlers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assignees = const TicketAssigneeOptions();
        _loadingHandlers = false;
        _error = 'Kunne ikke hente saksbehandlere: $e';
      });
    }
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
      setState(() => _error = 'Velg hvem som skal behandle avviket.');
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
          final url = await HmsEcosystemService.uploadAvvikMedia(
            companyId: companyId,
            bytes: _images[i].bytes,
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
        assignedTo: _selectedHandlerId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        severity: _severity,
        isAnonymous: _isAnonymous,
        imageUrls: imageUrls,
        status: TicketStatus.aapen,
        gpsLatitude: _gpsLat,
        gpsLongitude: _gpsLng,
        hmsDomain: _domain,
        hasPersonalInjury: _hasPersonalInjury,
        observedAt: DateTime.now(),
      );

      final created = await SupabaseService.createTicket(ticket);
      if (!mounted) return;
      final avvikId = created.ticketNumber != null
          ? 'Avvik #${created.ticketNumber}'
          : 'Avvik registrert';
      if (failedUploads > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$avvikId sendt. Saksbehandler får varsel. '
              '$failedUploads bilde(r) kunne ikke lastes opp.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$avvikId er registrert. Saksbehandler får varsel nå, '
              'og du får SMS ved statusendringer (under arbeid og ferdig).',
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

  Widget _buildAssigneePicker() {
    if (_assignees.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ingen saksbehandler funnet — sjekk at avdeling har leder registrert, '
              'eller kontakt HR.',
              style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loadHandlers,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Prøv igjen'),
            ),
          ],
        ),
      );
    }

    final defaultId = _assignees.defaultAssigneeId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Velg saksbehandler', style: DriftProTheme.labelLg),
        const SizedBox(height: 4),
        Text(
          'Systemet velger din leder automatisk. Du kan bytte til en annen leder eller superadmin.',
          style: DriftProTheme.bodySm.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        if (_assignees.nearestLeaders.isNotEmpty) ...[
          _assigneeSectionLabel('Din leder (anbefalt)', Icons.star_outline_rounded),
          const SizedBox(height: 6),
          ..._assignees.nearestLeaders.map(
            (p) => _assigneeTile(p, recommended: p.id == defaultId),
          ),
          const SizedBox(height: 8),
        ],
        if (_assignees.otherLeaders.isNotEmpty) ...[
          _assigneeSectionLabel('Andre ledere', Icons.groups_outlined),
          const SizedBox(height: 6),
          ..._assignees.otherLeaders.map((p) => _assigneeTile(p)),
          const SizedBox(height: 8),
        ],
        if (_assignees.superadmins.isNotEmpty) ...[
          _assigneeSectionLabel('Superadmin', Icons.admin_panel_settings_outlined),
          const SizedBox(height: 6),
          ..._assignees.superadmins.map((p) => _assigneeTile(p)),
        ],
      ],
    );
  }

  Widget _assigneeSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: DriftProTheme.primaryGreen),
        const SizedBox(width: 6),
        Text(
          label,
          style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  String _displayName(UserProfile p) {
    var name = p.fullName.trim();
    for (final suffix in [
      ' · Superadmin',
      ' · superadmin',
      ' - Superadmin',
      ' - superadmin',
    ]) {
      if (name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length).trim();
      }
    }
    return name.isEmpty ? p.fullName : name;
  }

  Widget _assigneeTile(UserProfile p, {bool recommended = false}) {
    final selected = _selectedHandlerId == p.id;
    final roleLabel = switch (p.role) {
      UserRole.superadmin => 'Superadmin',
      UserRole.admin => 'Administrator',
      UserRole.leder => 'Leder',
      _ => 'Saksbehandler',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? DriftProTheme.primaryGreen
              : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: RadioListTile<String>(
        value: p.id,
        groupValue: _selectedHandlerId,
        onChanged: (v) => setState(() => _selectedHandlerId = v),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _displayName(p),
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Anbefalt',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: DriftProTheme.primaryGreen,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '$roleLabel · får varsel når du sender',
          style: const TextStyle(fontSize: 11),
        ),
        activeColor: DriftProTheme.primaryGreen,
      ),
    );
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
                  Icon(Icons.sms_outlined, color: DriftProTheme.primaryGreen),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Velg hvem som skal behandle avviket. '
                      'Valgt person får SMS med en gang.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_templates.isNotEmpty) ...[
              Text('Hurtigmaler', style: DriftProTheme.labelLg),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _templates.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final t = _templates[i];
                    return ActionChip(
                      avatar: Icon(
                        t.domain == HmsDomain.logistikk
                            ? Icons.local_shipping_outlined
                            : Icons.report_outlined,
                        size: 18,
                      ),
                      label: Text(t.title),
                      onPressed: () => _applyTemplate(t),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: Text('Område', style: DriftProTheme.labelLg),
                ),
                if (_capturingGps)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_gpsLat != null)
                  Text(
                    'GPS OK',
                    style: TextStyle(
                      color: DriftProTheme.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.my_location_outlined, size: 20),
                  onPressed: _captureGps,
                  tooltip: 'Oppdater posisjon',
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: HmsDomain.values.map((d) {
                final sel = _domain == d;
                return FilterChip(
                  label: Text(d.label),
                  selected: sel,
                  onSelected: (_) => setState(() => _domain = d),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_loadingHandlers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _buildAssigneePicker(),
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
              value: _hasPersonalInjury,
              onChanged: (v) => setState(() => _hasPersonalInjury = v),
              title: const Text('Personskade / sensitive opplysninger'),
              subtitle: const Text(
                'Navn på skadde lagres kryptert og kun synlig for leder/HR.',
                style: TextStyle(fontSize: 12),
              ),
            ),
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
              onPressed: _isSubmitting ||
                      _loadingHandlers ||
                      _assignees.isEmpty ||
                      _selectedHandlerId == null
                  ? null
                  : _submit,
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
