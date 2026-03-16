import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms_document.dart';
import 'package:intl/intl.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({super.key});

  @override
  State<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  List<HmsDocument> _docs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final data = await SupabaseService.fetchHmsDocuments(companyId: companyId);
        setState(() => _docs = data);
      } else {
        setState(() => _docs = []);
      }
    } catch (_) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Mine Dokumenter'),
        actions: [
          IconButton(icon: const Icon(Icons.upload_file), onPressed: () => _uploadNew(context)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _docs.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _docs.length,
                      itemBuilder: (context, index) {
                        final d = _docs[index];
                        return _buildCard(d, isDark);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Text('Ingen dokumenter funnet.', style: TextStyle(color: Colors.grey)));
  }

  Widget _buildCard(HmsDocument d, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: DriftProTheme.primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.insert_drive_file_outlined, color: DriftProTheme.primaryGreen),
        ),
        title: Text(d.title, style: DriftProTheme.labelLg),
        subtitle: Text('${d.documentType.label} • Utløper: ${d.expiresAt != null ? DateFormat('dd.MM.yyyy').format(d.expiresAt!) : "Aldri"}', style: DriftProTheme.bodySm),
        trailing: const Icon(Icons.download_rounded, color: Colors.grey),
        onTap: () {
          // Open URL
        },
      ),
    );
  }

  void _uploadNew(BuildContext context) {
    // Show upload dialog
  }
}
