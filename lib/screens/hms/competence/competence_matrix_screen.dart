import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/hms/competence_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/competence_course.dart';
import '../../../models/hms_document.dart';
import '../../../models/user_profile.dart';

class CompetenceMatrixScreen extends StatefulWidget {
  const CompetenceMatrixScreen({super.key});

  @override
  State<CompetenceMatrixScreen> createState() => _CompetenceMatrixScreenState();
}

class _CompetenceMatrixScreenState extends State<CompetenceMatrixScreen> {
  bool _isLoading = true;
  List<UserProfile> _profiles = [];
  List<HmsDocument> _documents = [];
  List<CompetenceCourse> _courses = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) return;

      await CompetenceService.seedDefaults(companyId);
      final profiles = await SupabaseService.fetchMaviEmployees(companyId: companyId);
      final docs = await CompetenceService.fetchCompetenceDocuments(
        companyId: companyId,
      );
      var courses = await CompetenceService.fetchCourses(companyId);
      if (courses.isEmpty) {
        courses = [
          for (final n in [
            'Truckførerbevis',
            'Maskinførerbevis',
            'Førerkort',
            'Førstehjelp',
            'HMS-kurs',
          ])
            CompetenceCourse(id: n, companyId: companyId, name: n),
        ];
      }

      setState(() {
        _profiles = profiles;
        _documents = docs;
        _courses = courses;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  HmsDocument? _docFor(UserProfile p, CompetenceCourse course) {
    for (final d in _documents) {
      if (d.userId != p.id) continue;
      if (d.courseId == course.id) return d;
      if (d.title.toLowerCase().contains(course.name.toLowerCase())) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Kompetanse-matrise'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildMatrix(isDark),
    );
  }

  Widget _buildMatrix(bool isDark) {
    final skills = _courses.map((c) => c.name).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            isDark ? DriftProTheme.cardDark : Colors.grey[200],
          ),
          columns: [
            const DataColumn(
              label: Text('Ansatt', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...skills.map(
              (s) => DataColumn(
                label: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          rows: _profiles.map((p) => _buildProfileRow(p, isDark)).toList(),
        ),
      ),
    );
  }

  DataRow _buildProfileRow(UserProfile p, bool isDark) {
    return DataRow(
      cells: [
        DataCell(Text(p.fullName)),
        ..._courses.map((course) {
          final doc = _docFor(p, course);
          if (doc == null) {
            return const DataCell(Icon(Icons.cancel, color: Colors.red, size: 20));
          }
          if (doc.isExpired) {
            return DataCell(
              IconButton(
                icon: const Icon(Icons.warning, color: Colors.red),
                onPressed: () => launchUrl(Uri.parse(doc.fileUrl)),
              ),
            );
          }
          if (doc.expiresSoon) {
            return DataCell(
              IconButton(
                icon: const Icon(Icons.warning_amber, color: Colors.orange),
                onPressed: () => launchUrl(Uri.parse(doc.fileUrl)),
              ),
            );
          }
          return DataCell(
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => launchUrl(Uri.parse(doc.fileUrl)),
            ),
          );
        }),
      ],
    );
  }
}
