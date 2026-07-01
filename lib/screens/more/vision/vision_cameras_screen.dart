import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/vision/vision_camera_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../../models/vision_camera.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'vision_events_screen.dart';

/// Admin: legg til og endre IP-kameraer for vision monitor.
class VisionCamerasScreen extends StatefulWidget {
  const VisionCamerasScreen({super.key});

  @override
  State<VisionCamerasScreen> createState() => _VisionCamerasScreenState();
}

class _VisionCamerasScreenState extends State<VisionCamerasScreen> {
  List<VisionCamera> _cameras = [];
  bool _loading = true;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      final cameras = await VisionCameraService.instance.fetchCameras();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _cameras = cameras;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke laste kameraer: $e')),
      );
    }
  }

  bool get _canEdit =>
      _profile?.access.canUniformMonitorAdmin == true ||
      _profile?.isSuperAdmin == true;

  Future<void> _openEditor([VisionCamera? existing]) async {
    if (!_canEdit) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CameraEditorSheet(camera: existing),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kameraer'),
        actions: [
          IconButton(
            tooltip: 'Hendelser',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const VisionEventsScreen()),
            ),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Legg til'),
            )
          : null,
      body: _loading
          ? const DriftProLoadingCenter()
          : _cameras.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _cameras.length,
                    itemBuilder: (context, i) => _CameraCard(
                      camera: _cameras[i],
                      canEdit: _canEdit,
                      onEdit: () => _openEditor(_cameras[i]),
                      onDelete: () => _delete(_cameras[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Ingen kameraer', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            Text(
              'Legg til IP-kamera med adresse, bruker og passord.\n'
              'Eksempel: 192.168.39.190',
              textAlign: TextAlign.center,
              style: DriftProTheme.caption,
            ),
            if (_canEdit) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Legg til første kamera'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(VisionCamera cam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett kamera?'),
        content: Text('${cam.name} (${cam.host})'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await VisionCameraService.instance.deleteCamera(cam.id);
    await _load();
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.camera,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final VisionCamera camera;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: camera.enabled
              ? DriftProTheme.success.withValues(alpha: 0.15)
              : Colors.grey.shade300,
          child: Icon(
            Icons.videocam,
            color: camera.enabled ? DriftProTheme.success : Colors.grey,
          ),
        ),
        title: Text(camera.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${camera.host} · ${camera.eventTypeLabel}'
          '${camera.hasPassword ? '' : ' · mangler passord'}',
        ),
        trailing: canEdit
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Rediger')),
                  PopupMenuItem(value: 'delete', child: Text('Slett')),
                ],
              )
            : null,
        onTap: canEdit ? onEdit : null,
      ),
    );
  }
}

class _CameraEditorSheet extends StatefulWidget {
  const _CameraEditorSheet({this.camera});

  final VisionCamera? camera;

  @override
  State<_CameraEditorSheet> createState() => _CameraEditorSheetState();
}

class _CameraEditorSheetState extends State<_CameraEditorSheet> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '80');
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  String _eventType = 'uniform_violation';
  bool _enabled = true;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final c = widget.camera;
    if (c != null) {
      _name.text = c.name;
      _host.text = c.host;
      _port.text = '${c.httpPort}';
      _user.text = c.cameraUser;
      _eventType = c.eventType;
      _enabled = c.enabled;
    } else {
      _name.text = 'Kamera 1';
      _host.text = '192.168.39.190';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP-adresse er påkrevd')),
      );
      return;
    }
    if (widget.camera == null && _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passord er påkrevd for nytt kamera')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await VisionCameraService.instance.upsertCamera(
        id: widget.camera?.id,
        name: _name.text.trim().isEmpty ? 'Kamera' : _name.text.trim(),
        host: host,
        httpPort: int.tryParse(_port.text.trim()) ?? 80,
        cameraUser: _user.text.trim().isEmpty ? 'admin' : _user.text.trim(),
        cameraPassword: _password.text.isEmpty ? null : _password.text,
        eventType: _eventType,
        enabled: _enabled,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.camera == null ? 'Nytt kamera' : 'Rediger kamera',
              style: DriftProTheme.headingMd,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Navn',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'IP-adresse',
                hintText: '192.168.39.190',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.a-zA-Z-]')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _port,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _user,
                    decoration: const InputDecoration(
                      labelText: 'Bruker',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: widget.camera == null ? 'Passord' : 'Nytt passord (valgfritt)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _eventType,
              decoration: const InputDecoration(
                labelText: 'Hendelsestype',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'uniform_violation',
                  child: Text('Uniform (MAVI-logo + vernesko)'),
                ),
                DropdownMenuItem(value: 'ppe_violation', child: Text('PPE-brudd')),
                DropdownMenuItem(value: 'parking_entry', child: Text('Parkering inn')),
                DropdownMenuItem(value: 'parking_exit', child: Text('Parkering ut')),
              ],
              onChanged: (v) => setState(() => _eventType = v ?? _eventType),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktiv'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: DriftProLoadingIndicator(size: 20),
                    )
                  : const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
  }
}
