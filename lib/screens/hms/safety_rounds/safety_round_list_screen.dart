import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/safety_round.dart';
import 'package:intl/intl.dart';
import 'new_safety_round_screen.dart';

class SafetyRoundListScreen extends StatefulWidget {
  const SafetyRoundListScreen({super.key});

  @override
  State<SafetyRoundListScreen> createState() => _SafetyRoundListScreenState();
}

class _SafetyRoundListScreenState extends State<SafetyRoundListScreen> {
  List<SafetyRound> _rounds = [];
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
        final data = await SupabaseService.fetchSafetyRounds(companyId: companyId);
        setState(() => _rounds = data);
      } else {
        setState(() => _rounds = []);
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
        title: const Text('Vernerunder'),
        actions: [
          IconButton(icon: const Icon(AppIcons.add), onPressed: () => _createNew(context)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _rounds.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rounds.length,
                      itemBuilder: (context, index) {
                        final r = _rounds[index];
                        return _buildCard(r, isDark);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.safetyRound, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Ingen vernerunder registrert', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => _createNew(context), child: const Text('OPPRETT NY RUNDE')),
        ],
      ),
    );
  }

  Widget _buildCard(SafetyRound r, bool isDark) {
    final bool isCompleted = r.overallStatus == 'fullført';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: (isCompleted ? DriftProTheme.success : DriftProTheme.warning).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(AppIcons.safetyRound, color: isCompleted ? DriftProTheme.success : DriftProTheme.warning),
        ),
        title: Text(r.title, style: DriftProTheme.labelLg),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ansvarlig: ${r.conductorName ?? "Ukjent"}', style: DriftProTheme.bodySm),
            Text('Dato: ${r.scheduledDate != null ? DateFormat('dd.MM.yyyy').format(r.scheduledDate!) : "Ikke satt"}', style: DriftProTheme.bodySm),
          ],
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? Colors.grey[700] : Colors.grey[300]),
        onTap: () {
          // View detail
        },
      ),
    );
  }

  void _createNew(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSafetyRoundScreen())).then((v) { if (v == true) _loadData(); });
  }
}
