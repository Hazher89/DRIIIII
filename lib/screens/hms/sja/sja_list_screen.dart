import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/hms/hms_templates.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/sja_form.dart';
import 'package:intl/intl.dart';
import '../widgets/hms_template_picker_sheet.dart';
import 'new_sja_screen.dart';
import 'sja_detail_screen.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class SjaListScreen extends StatefulWidget {
  const SjaListScreen({super.key});

  @override
  State<SjaListScreen> createState() => _SjaListScreenState();
}

class _SjaListScreenState extends State<SjaListScreen> {
  List<SjaForm> _forms = [];
  Map<String, String> _profileNames = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final data = await SupabaseService.fetchSjaForms(companyId: companyId);
        final profiles = await SupabaseService.fetchProfiles(companyId: companyId);
        final names = {for (final p in profiles) p.id: p.fullName};
        setState(() {
          _forms = data;
          _profileNames = names;
        });
      } else {
        setState(() => _forms = []);
      }
    } catch (e) {
      setState(() => _loadError = 'Kunne ikke hente SJA: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _name(String? id) =>
      id == null ? 'Ikke angitt' : (_profileNames[id] ?? 'Ukjent');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Sikker Jobb Analyse (SJA)'),
        actions: [
          IconButton(icon: const Icon(AppIcons.add), onPressed: () => _createNew(context)),
        ],
      ),
      body: _isLoading
          ? const DriftProLoadingCenter()
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadData, child: const Text('Prøv igjen')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: _loadData,
              child: _forms.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _forms.length,
                      itemBuilder: (context, index) {
                        final f = _forms[index];
                        return _buildCard(f, isDark);
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
          Icon(AppIcons.sja, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Ingen SJA-skjemaer funnet', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => _createNew(context), child: const Text('OPPRETT NY SJA')),
        ],
      ),
    );
  }

  Widget _buildCard(SjaForm f, bool isDark) {
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
          decoration: BoxDecoration(color: f.status.color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(Icons.assignment_turned_in_outlined, color: f.status.color),
        ),
        title: Text(f.title, style: DriftProTheme.labelLg),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sted: ${f.location ?? "Ikke angitt"}', style: DriftProTheme.bodySm),
            Text('Ansvarlig: ${_name(f.responsiblePerson)}', style: DriftProTheme.bodySm),
            Text('Opprettet av: ${_name(f.createdBy)}', style: DriftProTheme.bodySm),
            Text('Planlagt: ${DateFormat('dd.MM.yyyy').format(f.plannedDate)}', style: DriftProTheme.bodySm),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: f.status.color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(f.status.label, style: TextStyle(color: f.status.color, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SjaDetailScreen(form: f)),
          ).then((_) => _loadData());
        },
      ),
    );
  }

  void _createNew(BuildContext context) {
    HmsTemplatePickerSheet.show(
      context,
      kind: HmsModuleKind.sja,
      onSelected: (t) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewSjaScreen(template: t as HmsSjaTemplate)),
      ).then((v) { if (v == true) _loadData(); }),
      onBlank: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NewSjaScreen()),
      ).then((v) { if (v == true) _loadData(); }),
    );
  }
}
