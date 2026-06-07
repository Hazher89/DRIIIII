import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/hms/stakeholder_risk_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/hms/stakeholder_risk_assessment.dart';
import 'stakeholder_risk_editor_screen.dart';

class StakeholderRiskHubTab extends StatefulWidget {
  const StakeholderRiskHubTab({super.key});

  @override
  State<StakeholderRiskHubTab> createState() => _StakeholderRiskHubTabState();
}

class _StakeholderRiskHubTabState extends State<StakeholderRiskHubTab> {
  List<StakeholderRiskAssessment> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        setState(() => _items = []);
        return;
      }
      final data = await StakeholderRiskService.fetchAll(companyId);
      if (mounted) setState(() => _items = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createNew() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (companyId == null || userId == null) return;
    if (!mounted) return;

    final year = DateTime.now().year;
    final titleCtrl = TextEditingController(
      text: 'Interessepart og risikovurdering $year',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ny vurdering fra mal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Oppretter en komplett vurdering basert på Excel-malen med '
              'interesseparter, interne/eksterne forhold og prosessrisiko.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Tittel',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Opprett')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final created = await StakeholderRiskService.createFromTemplate(
        companyId: companyId,
        createdBy: userId,
        title: titleCtrl.text.trim(),
        year: year,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StakeholderRiskEditorScreen(assessmentId: created.id),
        ),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke opprette: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Prøv igjen')),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Icon(Icons.groups_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'Ingen interessepart-vurderinger ennå',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Opprett en ny vurdering med full mal fra Excel-filen — '
              'interesseparter, interne/eksterne forhold og prosessrisiko.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: _createNew,
              icon: const Icon(Icons.add),
              label: const Text('Ny vurdering fra mal'),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return _card(item, isDark);
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _createNew,
            icon: const Icon(Icons.add),
            label: const Text('Ny vurdering'),
          ),
        ),
      ],
    );
  }

  Widget _card(StakeholderRiskAssessment item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
          child: const Icon(Icons.groups, color: DriftProTheme.primaryGreen),
        ),
        title: Text(item.title, style: DriftProTheme.labelLg),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${item.totalRows} rader · ${item.highRiskCount} høyrisiko'),
            if (item.updatedAt != null)
              Text(
                'Oppdatert ${DateFormat('dd.MM.yyyy HH:mm').format(item.updatedAt!.toLocal())}',
                style: DriftProTheme.caption,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StakeholderRiskEditorScreen(assessmentId: item.id),
            ),
          );
          _load();
        },
      ),
    );
  }
}
