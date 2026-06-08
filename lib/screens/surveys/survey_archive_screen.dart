import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/services/survey/survey_advanced_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey_advanced.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class SurveyArchiveScreen extends StatefulWidget {
  const SurveyArchiveScreen({super.key});

  @override
  State<SurveyArchiveScreen> createState() => _SurveyArchiveScreenState();
}

class _SurveyArchiveScreenState extends State<SurveyArchiveScreen> {
  bool _isLoading = true;
  List<SurveyArchiveEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final companyId = profile?.companyId;
      if (companyId == null) {
        setState(() {
          _entries = const [];
          _isLoading = false;
        });
        return;
      }
      final rows = await SurveyAdvancedService.fetchArchive(companyId: companyId);
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Klarte ikke hente arkiv: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Survey-arkiv'),
        actions: [
          IconButton(onPressed: _loadArchive, icon: const Icon(Icons.refresh)),
        ],
      ),
      backgroundColor: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF5F7F8),
      body: _isLoading
          ? const DriftProLoadingCenter()
          : _entries.isEmpty
              ? const Center(child: Text('Ingen arkiverte undersøkelser enda'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return ListTile(
                      tileColor: isDark ? DriftProTheme.cardDark : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(e.title),
                      subtitle: Text(
                        '${e.responsesAtArchive} svar • ${e.archivedAt.day}.${e.archivedAt.month}.${e.archivedAt.year}',
                      ),
                      trailing: Text(e.status.toUpperCase()),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemCount: _entries.length,
                ),
    );
  }
}

