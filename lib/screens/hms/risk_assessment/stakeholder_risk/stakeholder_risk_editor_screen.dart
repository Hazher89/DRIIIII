import 'package:flutter/material.dart';

import '../../../../core/services/hms/hms_pdf_generators.dart';
import '../../../../core/services/hms/stakeholder_risk_service.dart';
import '../../widgets/hms_pdf_export_button.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/hms/stakeholder_risk_assessment.dart';
import 'stakeholder_risk_widgets.dart';

class StakeholderRiskEditorScreen extends StatefulWidget {
  final String assessmentId;

  const StakeholderRiskEditorScreen({super.key, required this.assessmentId});

  @override
  State<StakeholderRiskEditorScreen> createState() =>
      _StakeholderRiskEditorScreenState();
}

class _StakeholderRiskEditorScreenState extends State<StakeholderRiskEditorScreen>
    with SingleTickerProviderStateMixin {
  StakeholderRiskAssessment? _assessment;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await StakeholderRiskService.fetchById(widget.assessmentId);
      if (mounted) {
        setState(() => _assessment = item);
        if (item == null) _error = 'Fant ikke vurderingen';
      }
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final a = _assessment;
    if (a == null) return;
    setState(() => _saving = true);
    try {
      final updated = await StakeholderRiskService.update(a);
      if (mounted) {
        setState(() => _assessment = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lagring feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _updateSection(int index, StakeholderRiskSection section) {
    final a = _assessment;
    if (a == null) return;
    final sections = List<StakeholderRiskSection>.from(a.content.sections);
    sections[index] = section;
    setState(() {
      _assessment = a.copyWith(
        content: a.content.copyWith(sections: sections),
      );
    });
  }

  Future<void> _editTitle() async {
    final a = _assessment;
    if (a == null) return;
    final ctrl = TextEditingController(text: a.title);
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger tittel'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    if (ok != null && ok.isNotEmpty) {
      setState(() => _assessment = a.copyWith(title: ok));
    }
  }

  Future<void> _editColumnLabels() async {
    final a = _assessment;
    if (a == null) return;
    final section = a.content.sections[_tabController.index];
    final labels = Map<String, String>.from(section.columnLabels);
    final keys = section.columnKeys;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rediger kolonne-etiketter', style: DriftProTheme.headingSm),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: keys.length,
                      itemBuilder: (_, i) {
                        final key = keys[i];
                        final ctrl = TextEditingController(text: labels[key] ?? key);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              labelText: key,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (v) => labels[key] = v,
                          ),
                        );
                      },
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      _updateSection(
                        _tabController.index,
                        section.copyWith(columnLabels: labels),
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text('Bruk etiketter'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _sectionIcon(String icon) {
    switch (icon) {
      case 'groups':
        return Icons.groups_outlined;
      case 'balance':
        return Icons.balance_outlined;
      case 'account_tree':
        return Icons.account_tree_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editTitle,
          child: Text(
            _assessment?.title ?? 'Interessepart',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          if (_assessment != null)
            HmsPdfExportButton(
              fileName: 'interessepart_${_assessment!.id.substring(0, 8)}',
              onGenerate: () => HmsPdfGenerators.stakeholderRisk(_assessment!),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Lagre',
              onPressed: _save,
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'labels') _editColumnLabels();
              if (v == 'delete') _confirmDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'labels', child: Text('Rediger kolonne-etiketter')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Slett vurdering', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
        bottom: _assessment == null
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _assessment!.content.sections
                    .map(
                      (s) => Tab(
                        icon: Icon(_sectionIcon(s.icon), size: 18),
                        text: _shortTabTitle(s.title),
                      ),
                    )
                    .toList(),
              ),
      ),
      floatingActionButton: _assessment == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Lagre'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _assessment == null
                  ? const Center(child: Text('Ingen data'))
                  : Column(
                      children: [
                        StakeholderRiskSummary(assessment: _assessment!),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              for (var i = 0; i < _assessment!.content.sections.length; i++)
                                StakeholderRiskSectionView(
                                  section: _assessment!.content.sections[i],
                                  onChanged: (s) => _updateSection(i, s),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  String _shortTabTitle(String title) {
    if (title.contains('Interessepart')) return 'Interesseparter';
    if (title.contains('forhold')) return 'Forhold';
    if (title.contains('PROSESS')) return 'Prosesser';
    return title.length > 18 ? '${title.substring(0, 16)}…' : title;
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett vurdering?'),
        content: const Text('Dette kan ikke angres.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await StakeholderRiskService.delete(widget.assessmentId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sletting feilet: $e')),
        );
      }
    }
  }
}
