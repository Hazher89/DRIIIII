import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/hms/stakeholder_risk_template_loader.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/hms/stakeholder_risk_assessment.dart';

class StakeholderRiskSummary extends StatelessWidget {
  final StakeholderRiskAssessment assessment;

  const StakeholderRiskSummary({super.key, required this.assessment});

  @override
  Widget build(BuildContext context) {
    final high = assessment.highRiskCount;
    final total = assessment.totalRows;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: 0.9),
            DriftProTheme.accentBlue.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.title,
            style: DriftProTheme.labelLg.copyWith(color: Colors.white),
          ),
          if (assessment.assessmentYear != null)
            Text(
              'Vurderingsår ${assessment.assessmentYear}',
              style: DriftProTheme.caption.copyWith(color: Colors.white70),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _chip(Icons.table_rows, '$total rader', Colors.white),
              const SizedBox(width: 8),
              _chip(Icons.warning_amber_rounded, '$high høyrisiko', Colors.orange.shade100),
              const SizedBox(width: 8),
              _chip(Icons.layers, '${assessment.content.sections.length} seksjoner', Colors.white70),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Basert på ${assessment.content.sourceFile}',
            style: DriftProTheme.caption.copyWith(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class StakeholderRowCard extends StatefulWidget {
  final StakeholderRiskSection section;
  final StakeholderRiskRow row;
  final ValueChanged<StakeholderRiskRow> onChanged;
  final VoidCallback? onDelete;

  const StakeholderRowCard({
    super.key,
    required this.section,
    required this.row,
    required this.onChanged,
    this.onDelete,
  });

  @override
  State<StakeholderRowCard> createState() => _StakeholderRowCardState();
}

class _StakeholderRowCardState extends State<StakeholderRowCard> {
  bool _expanded = false;

  String get _primaryLabel {
    final keys = widget.section.columnKeys;
    if (keys.isEmpty) return 'Rad';
    return widget.row.cells[keys.first]?.trim().isNotEmpty == true
        ? widget.row.cells[keys.first]!
        : 'Ny rad';
  }

  int? get _riskScore =>
      StakeholderRiskTemplateLoader.parseRiskScore(widget.section, widget.row.cells);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final score = _riskScore;
    final tier = score != null ? StakeholderRiskTemplateLoader.riskTier(score) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _tierColor(tier).withValues(alpha: 0.35),
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (score != null)
                    Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: _tierColor(tier).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$score',
                            style: TextStyle(
                              color: _tierColor(tier),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            StakeholderRiskTemplateLoader.riskLevelLabel(score),
                            style: TextStyle(color: _tierColor(tier), fontSize: 8),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_primaryLabel, style: DriftProTheme.labelMd),
                        if (widget.row.cells['requirements']?.isNotEmpty == true)
                          Text(
                            widget.row.cells['requirements']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DriftProTheme.caption,
                          )
                        else if (widget.row.cells['riskDescription']?.isNotEmpty == true)
                          Text(
                            widget.row.cells['riskDescription']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DriftProTheme.caption,
                          )
                        else if (widget.row.cells['negativeImpact']?.isNotEmpty == true)
                          Text(
                            widget.row.cells['negativeImpact']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DriftProTheme.caption,
                          ),
                      ],
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      onPressed: widget.onDelete,
                    ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildFieldGroups(isDark),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildFieldGroups(bool isDark) {
    final keys = widget.section.columnKeys;
    final labels = widget.section.columnLabels;
    final numeric = widget.section.numericKeys.toSet();

    String labelFor(String key) => labels[key] ?? key;

    final textKeys = keys.where((k) => !numeric.contains(k)).toList();
    final numKeys = keys.where((k) => numeric.contains(k)).toList();

    return [
      if (textKeys.isNotEmpty) ...[
        _groupTitle('Beskrivelse og tiltak', isDark),
        ...textKeys.map((k) => _field(labelFor(k), k, maxLines: k.contains('Description') || k.contains('Impact') || k.contains('Measures') || k.contains('opportunities') || k.contains('requirements') ? 4 : 2)),
      ],
      if (numKeys.isNotEmpty) ...[
        const SizedBox(height: 12),
        _groupTitle('Risikoscore og oppfølging', isDark),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: numKeys.map((k) => SizedBox(
            width: 140,
            child: _field(labelFor(k), k, maxLines: 1, isNumeric: true),
          )).toList(),
        ),
      ],
    ];
  }

  Widget _groupTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: DriftProTheme.labelSm.copyWith(
          color: isDark ? Colors.grey[500] : Colors.grey[500],
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _field(String label, String key, {int maxLines = 2, bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        initialValue: widget.row.cells[key] ?? '',
        maxLines: maxLines,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.multiline,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) {
          final cells = Map<String, String>.from(widget.row.cells);
          cells[key] = v;
          final updated = StakeholderRiskTemplateLoader.applyAutoRiskScores(widget.section, cells);
          widget.onChanged(widget.row.copyWith(cells: updated));
        },
      ),
    );
  }

  Color _tierColor(ColorRiskTier? tier) {
    switch (tier) {
      case ColorRiskTier.low:
        return DriftProTheme.riskLow;
      case ColorRiskTier.medium:
        return DriftProTheme.riskMedium;
      case ColorRiskTier.high:
        return DriftProTheme.riskHigh;
      case ColorRiskTier.critical:
        return DriftProTheme.riskCritical;
      case null:
        return Colors.grey;
    }
  }
}

class StakeholderRiskSectionView extends StatelessWidget {
  final StakeholderRiskSection section;
  final ValueChanged<StakeholderRiskSection> onChanged;

  const StakeholderRiskSectionView({
    super.key,
    required this.section,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _documentTitleCard(isDark),
        const SizedBox(height: 12),
        ...section.groups.map((g) => _groupBlock(context, g, isDark)),
        if (section.rows.isNotEmpty) ...[
          if (section.groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Øvrige', style: DriftProTheme.labelMd),
            ),
          ...section.rows.map((r) => _rowCard(r, groupId: null)),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _addRow(groupId: null),
          icon: const Icon(Icons.add),
          label: const Text('Legg til rad'),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _documentTitleCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: TextFormField(
        initialValue: section.documentTitle,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Dokumenttittel (redigerbar)',
          border: InputBorder.none,
        ),
        style: DriftProTheme.labelMd,
        onChanged: (v) => onChanged(section.copyWith(documentTitle: v)),
      ),
    );
  }

  Widget _groupBlock(BuildContext context, StakeholderRiskGroup group, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: group.title,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Gruppetittel',
                  ),
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w700),
                  onChanged: (v) {
                    final groups = section.groups.map((g) {
                      if (g.id == group.id) return g.copyWith(title: v);
                      return g;
                    }).toList();
                    onChanged(section.copyWith(groups: groups));
                  },
                ),
              ),
              IconButton(
                tooltip: 'Legg til rad i gruppe',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _addRow(groupId: group.id),
              ),
            ],
          ),
        ),
        ...group.rows.map((r) => _rowCard(r, groupId: group.id)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _rowCard(StakeholderRiskRow row, {required String? groupId}) {
    return StakeholderRowCard(
      section: section,
      row: row,
      onChanged: (updated) => _updateRow(updated, groupId: groupId),
      onDelete: () => _deleteRow(row.id, groupId: groupId),
    );
  }

  void _updateRow(StakeholderRiskRow row, {required String? groupId}) {
    if (groupId == null) {
      final rows = section.rows.map((r) => r.id == row.id ? row : r).toList();
      onChanged(section.copyWith(rows: rows));
      return;
    }
    final groups = section.groups.map((g) {
      if (g.id != groupId) return g;
      return g.copyWith(
        rows: g.rows.map((r) => r.id == row.id ? row : r).toList(),
      );
    }).toList();
    onChanged(section.copyWith(groups: groups));
  }

  void _deleteRow(String rowId, {required String? groupId}) {
    if (groupId == null) {
      onChanged(section.copyWith(
        rows: section.rows.where((r) => r.id != rowId).toList(),
      ));
      return;
    }
    final groups = section.groups.map((g) {
      if (g.id != groupId) return g;
      return g.copyWith(rows: g.rows.where((r) => r.id != rowId).toList());
    }).toList();
    onChanged(section.copyWith(groups: groups));
  }

  void _addRow({required String? groupId}) {
    const uuid = Uuid();
    final keys = section.columnKeys;
    final emptyCells = {for (final k in keys) k: ''};
    final newRow = StakeholderRiskRow(id: uuid.v4(), cells: emptyCells);

    if (groupId == null) {
      onChanged(section.copyWith(rows: [...section.rows, newRow]));
      return;
    }
    final groups = section.groups.map((g) {
      if (g.id != groupId) return g;
      return g.copyWith(rows: [...g.rows, newRow]);
    }).toList();
    onChanged(section.copyWith(groups: groups));
  }
}
