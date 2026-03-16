import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/user_profile.dart';
import '../../../models/hms_document.dart';

class CompetenceMatrixScreen extends StatefulWidget {
  const CompetenceMatrixScreen({super.key});

  @override
  State<CompetenceMatrixScreen> createState() => _CompetenceMatrixScreenState();
}

class _CompetenceMatrixScreenState extends State<CompetenceMatrixScreen> {
  bool _isLoading = true;
  List<UserProfile> _profiles = [];
  List<HmsDocument> _documents = [];
  final List<String> _requiredSkills = ['Førerkort', 'Truckførerbevis', 'Maskinførerbevis', 'Førstehjelp', 'HMS-kurs'];

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

      final profilesFut = SupabaseService.fetchProfiles(companyId: companyId);
      final docsFut = SupabaseService.client
          .from('hms_documents')
          .select()
          .eq('company_id', companyId);
      
      final res = await Future.wait([
        profilesFut as Future<dynamic>,
        docsFut as Future<dynamic>,
      ]);
      
      setState(() {
        _profiles = res[0] as List<UserProfile>;
        _documents = (res[1] as List).map((e) => HmsDocument.fromJson(e as Map<String, dynamic>)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Kompetanse-matrise'),
        actions: [
          IconButton(icon: const Icon(Icons.file_download_outlined), onPressed: () {}),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _buildMatrix(isDark),
    );
  }

  Widget _buildMatrix(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(isDark ? DriftProTheme.cardDark : Colors.grey[200]),
          columns: [
            const DataColumn(label: Text('Ansatt', style: TextStyle(fontWeight: FontWeight.bold))),
            ..._requiredSkills.map((s) => DataColumn(label: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)))),
          ],
          rows: _profiles.map((p) => _buildProfileRow(p, isDark)).toList(),
        ),
      ),
    );
  }

  DataRow _buildProfileRow(UserProfile profile, bool isDark) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(radius: 14, child: Text(profile.fullName[0], style: const TextStyle(fontSize: 10))),
              const SizedBox(width: 8),
              Text(profile.fullName, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        ..._requiredSkills.map((skill) {
          final doc = _documents.where((d) => d.userId == profile.id && d.title.toLowerCase().contains(skill.toLowerCase())).firstOrNull;
          return _buildStatusCell(doc);
        }),
      ],
    );
  }

  DataCell _buildStatusCell(HmsDocument? doc) {
    if (doc == null) {
      return const DataCell(Icon(Icons.close_rounded, color: Colors.grey, size: 18));
    }

    final isExpired = doc.expiresAt != null && doc.expiresAt!.isBefore(DateTime.now());
    final isExpiringSoon = doc.expiresAt != null && doc.expiresAt!.isBefore(DateTime.now().add(const Duration(days: 30)));

    Color color = Colors.green;
    if (isExpired) color = Colors.red;
    else if (isExpiringSoon) color = Colors.orange;

    return DataCell(
      Tooltip(
        message: doc.expiresAt != null ? 'Utløper: ${doc.expiresAt!.day}.${doc.expiresAt!.month}.${doc.expiresAt!.year}' : 'Ingen utløpsdato',
        child: Icon(Icons.check_circle_rounded, color: color, size: 20),
      ),
    );
  }
}
