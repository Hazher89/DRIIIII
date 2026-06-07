import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/services/hms/competence_service.dart';
import '../../../core/services/hms/employee_document_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/competence_course.dart';
import '../../../models/hms_document.dart';
import '../../../models/user_profile.dart';
import 'competence_matrix_screen.dart';

/// Kompetanse: kurskatalog, dokumenter/bevis, matrise.
class CompetenceHubScreen extends StatefulWidget {
  const CompetenceHubScreen({super.key});

  @override
  State<CompetenceHubScreen> createState() => _CompetenceHubScreenState();
}

class _CompetenceHubScreenState extends State<CompetenceHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  UserProfile? _me;
  List<CompetenceCourse> _courses = [];
  List<HmsDocument> _documents = [];
  List<UserProfile> _profiles = [];
  bool _loading = true;

  bool get _canManage =>
      _me?.isSuperAdmin == true ||
      _me?.role == UserRole.admin ||
      _me?.role == UserRole.leder;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _me = await SupabaseService.fetchCurrentUserProfile();
      final companyId = _me?.companyId;
      if (companyId == null) return;
      await CompetenceService.seedDefaults(companyId);
      final courses = await CompetenceService.fetchCourses(companyId);
      if (courses.isEmpty) {
        await CompetenceService.seedDefaults(companyId);
      }
      _courses = await CompetenceService.fetchCourses(companyId);
      _documents = await CompetenceService.fetchCompetenceDocuments(
        companyId: companyId,
      );
      _profiles = await SupabaseService.fetchMaviEmployees(companyId: companyId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _profileName(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p.fullName;
    }
    return 'Ukjent';
  }

  String? _courseName(String? courseId) {
    if (courseId == null) return null;
    for (final c in _courses) {
      if (c.id == courseId) return c.name;
    }
    return null;
  }

  Future<void> _addCourse() async {
    final companyId = _me?.companyId;
    if (companyId == null || !_canManage) return;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var mandatory = false;
    var months = 60;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nytt kurs / kompetanse'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Kursnavn *'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Beskrivelse'),
                  maxLines: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Obligatorisk'),
                  value: mandatory,
                  onChanged: (v) => setD(() => mandatory = v),
                ),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Gyldighet (måneder)',
                  ),
                  onChanged: (v) => months = int.tryParse(v) ?? 60,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await CompetenceService.saveCourse(
      CompetenceCourse(
        id: '',
        companyId: companyId,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.isEmpty ? null : descCtrl.text,
        isMandatory: mandatory,
        defaultValidityMonths: months,
        sortOrder: _courses.length * 10,
      ),
    );
    _load();
  }

  Future<void> _uploadCertificate() async {
    final companyId = _me?.companyId;
    if (companyId == null || _me == null) return;

    String? userId = _profiles.length == 1 ? _profiles.first.id : null;
    String? courseId;
    final titleCtrl = TextEditingController();
    DateTime? expires;
    var type = HmsDocumentType.kursbevis;
    var employeeVisible = true;

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Last opp kursbevis / sertifikat'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: userId,
                  decoration: const InputDecoration(labelText: 'Ansatt *'),
                  items: _profiles
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.fullName)))
                      .toList(),
                  onChanged: (v) => setD(() => userId = v),
                ),
                DropdownButtonFormField<String>(
                  value: courseId,
                  decoration: const InputDecoration(labelText: 'Kurs (valgfritt)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ..._courses.map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ),
                  ],
                  onChanged: (v) => setD(() => courseId = v),
                ),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Tittel *'),
                ),
                DropdownButtonFormField<HmsDocumentType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: HmsDocumentType.kursbevis,
                      child: Text('Kursbevis'),
                    ),
                    DropdownMenuItem(
                      value: HmsDocumentType.sertifikat,
                      child: Text('Sertifikat'),
                    ),
                  ],
                  onChanged: (v) => setD(() => type = v ?? HmsDocumentType.kursbevis),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Utløpsdato'),
                  subtitle: Text(
                    expires != null
                        ? '${expires!.day}.${expires!.month}.${expires!.year}'
                        : 'Valgfritt',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 365)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setD(() => expires = d);
                  },
                ),
                if (_canManage)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ansatt kan se i personalmappe'),
                    value: employeeVisible,
                    onChanged: (v) => setD(() => employeeVisible = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                userId != null && titleCtrl.text.trim().isNotEmpty,
              ),
              child: const Text('Velg fil'),
            ),
          ],
        ),
      ),
    );
    if (step1 != true || userId == null) return;

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.single.bytes == null) return;
    final f = picked.files.single;

  if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final url = await EmployeeDocumentService.uploadFile(
        companyId: companyId,
        userId: userId!,
        fileName: f.name,
        bytes: f.bytes!,
      );
      await EmployeeDocumentService.uploadForEmployee(
        userId: userId!,
        companyId: companyId,
        uploadedBy: _me!.id,
        type: type,
        title: titleCtrl.text.trim(),
        fileUrl: url,
        fileName: f.name,
        fileSize: f.size,
        expiresAt: expires,
        employeeVisible: employeeVisible,
        courseId: courseId,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dokument lastet opp')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kompetanse & kurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_on_outlined),
            tooltip: 'Matrise',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CompetenceMatrixScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Kurs'),
            Tab(text: 'Bevis & dokumenter'),
            Tab(text: 'Oversikt'),
          ],
        ),
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _tabs.index == 0 ? _addCourse : _uploadCertificate,
              icon: Icon(_tabs.index == 0 ? Icons.add : Icons.upload_file),
              label: Text(_tabs.index == 0 ? 'Nytt kurs' : 'Last opp'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _coursesTab(),
                _documentsTab(),
                _overviewTab(),
              ],
            ),
    );
  }

  Widget _coursesTab() {
    if (_courses.isEmpty) {
      return const Center(child: Text('Ingen kurs — trykk + for å legge til'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _courses.length,
      itemBuilder: (_, i) {
        final c = _courses[i];
        final linked = _documents.where((d) => d.courseId == c.id).length;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
              child: Text('${c.sortOrder}', style: const TextStyle(fontSize: 12)),
            ),
            title: Text(c.name),
            subtitle: Text(
              '${c.category}${c.isMandatory ? ' · Obligatorisk' : ''} · $linked bevis',
            ),
            trailing: c.isMandatory
                ? const Icon(Icons.star, color: Colors.amber, size: 20)
                : null,
          ),
        );
      },
    );
  }

  Widget _documentsTab() {
    if (_documents.isEmpty) {
      return const Center(child: Text('Ingen kursbevis ennå'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _documents.length,
      itemBuilder: (_, i) {
        final d = _documents[i];
        Color? border;
        if (d.isExpired) border = DriftProTheme.error;
        else if (d.expiresSoon) border = DriftProTheme.warning;

        return Card(
          shape: RoundedRectangleBorder(
            side: BorderSide(color: border ?? Colors.transparent),
          ),
          child: ListTile(
            leading: Icon(
              d.documentType == HmsDocumentType.sertifikat
                  ? Icons.verified_outlined
                  : Icons.school_outlined,
              color: DriftProTheme.primaryGreen,
            ),
            title: Text(d.title),
            subtitle: Text(
              '${_profileName(d.userId)}'
              '${_courseName(d.courseId) != null ? ' · ${_courseName(d.courseId)}' : ''}'
              '${d.expiresAt != null ? '\nUtløper ${d.expiresAt!.day}.${d.expiresAt!.month}.${d.expiresAt!.year}' : ''}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(d.fileUrl)),
            ),
          ),
        );
      },
    );
  }

  Widget _overviewTab() {
    final expiring = _documents.where((d) => d.expiresSoon || d.isExpired).length;
    final mandatory = _courses.where((c) => c.isMandatory).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Kurs i katalog', '${_courses.length}', Icons.menu_book_outlined),
        _kpi('Obligatoriske', '$mandatory', Icons.star_outline),
        _kpi('Dokumenter', '${_documents.length}', Icons.folder_outlined),
        _kpi('Utløper snart', '$expiring', Icons.warning_amber_outlined,
            color: expiring > 0 ? DriftProTheme.warning : null),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CompetenceMatrixScreen()),
            );
          },
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Åpne kompetanse-matrise'),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value, IconData icon, {Color? color}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: color ?? DriftProTheme.primaryGreen),
        title: Text(label),
        trailing: Text(value, style: DriftProTheme.headingMd),
      ),
    );
  }
}
