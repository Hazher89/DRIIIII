import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/norwegian_national_id.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import 'employee_display.dart';

/// Bursdagskalender + registrering av fødselsnummer.
class EmployeeBirthdaysTab extends StatefulWidget {
  final List<UserProfile> employees;
  final List<Department> departments;
  final bool canEdit;
  final VoidCallback onChanged;

  const EmployeeBirthdaysTab({
    super.key,
    required this.employees,
    required this.departments,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  State<EmployeeBirthdaysTab> createState() => _EmployeeBirthdaysTabState();
}

class _BirthdayRow {
  final UserProfile profile;
  final DateTime? birthday;
  final int? daysUntil;
  final int? ageNext;

  const _BirthdayRow({
    required this.profile,
    this.birthday,
    this.daysUntil,
    this.ageNext,
  });
}

class _EmployeeBirthdaysTabState extends State<EmployeeBirthdaysTab> {
  String _filter = 'kommende';

  DateTime? _effectiveBirthday(UserProfile p) {
    return p.birthDate ?? NorwegianNationalId.birthDateFrom(p.nationalIdNumber);
  }

  List<_BirthdayRow> get _rows {
    final list = <_BirthdayRow>[];
    for (final p in widget.employees) {
      if (!p.isActive) continue;
      final bday = _effectiveBirthday(p);
      if (bday == null) {
        list.add(_BirthdayRow(profile: p));
        continue;
      }
      list.add(
        _BirthdayRow(
          profile: p,
          birthday: bday,
          daysUntil: NorwegianNationalId.daysUntilNextBirthday(bday),
          ageNext: NorwegianNationalId.ageOnNextBirthday(bday),
        ),
      );
    }

    switch (_filter) {
      case 'mangler':
        return list.where((r) => r.birthday == null).toList()
          ..sort((a, b) => a.profile.fullName.compareTo(b.profile.fullName));
      case 'maaned':
        final now = DateTime.now();
        return list
            .where((r) =>
                r.birthday != null && r.birthday!.month == now.month)
            .toList()
          ..sort((a, b) => a.birthday!.day.compareTo(b.birthday!.day));
      case 'kommende':
      default:
        final withBday = list.where((r) => r.birthday != null).toList()
          ..sort((a, b) => (a.daysUntil ?? 999).compareTo(b.daysUntil ?? 999));
        return withBday;
    }
  }

  int get _missingCount =>
      widget.employees.where((p) => _effectiveBirthday(p) == null && p.isActive).length;

  String _deptName(String? id) {
    if (id == null) return '—';
    for (final d in widget.departments) {
      if (d.id == id) return d.name;
    }
    return '—';
  }

  Future<void> _editNationalId(UserProfile p) async {
    final ctrl = TextEditingController(
      text: NorwegianNationalId.formatDisplay(p.nationalIdNumber),
    );
    var saving = false;
    String? previewDate;

    void updatePreview() {
      final parsed = NorwegianNationalId.birthDateFrom(ctrl.text);
      previewDate = parsed != null
          ? '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}'
          : null;
    }

    updatePreview();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.fullName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  if (p.employeeNumber != null && p.employeeNumber!.isNotEmpty)
                    Text(
                      'Ansattnr. ${p.employeeNumber}',
                      style: TextStyle(color: DriftProTheme.primaryGreen, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    maxLength: 13,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\s]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Fødselsnummer (11 siffer)',
                      hintText: 'ddmmåå xxxxx',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (_) => setLocal(updatePreview),
                  ),
                  if (previewDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Fødselsdato fra nummer: $previewDate',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setLocal(() => saving = true);
                            try {
                              final normalized = NorwegianNationalId.normalize(ctrl.text);
                              if (ctrl.text.trim().isNotEmpty && normalized == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Fødselsnummer må være 11 siffer'),
                                  ),
                                );
                                return;
                              }
                              final parsed = NorwegianNationalId.birthDateFrom(normalized);
                              await SupabaseService.updateEmployeeProfile(
                                p.id,
                                nationalIdNumber: ctrl.text.trim(),
                                birthDate: parsed ?? p.birthDate,
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
                                );
                              }
                            } finally {
                              if (ctx.mounted) setLocal(() => saving = false);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Lagre', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (ok == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Text(
              'Registrer fødselsnummer (11 siffer) per ansatt — bursdag hentes automatisk. '
              '$_missingCount ansatte mangler ennå data.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'kommende', label: Text('Kommende')),
              ButtonSegment(value: 'maaned', label: Text('Denne mnd.')),
              ButtonSegment(value: 'mangler', label: Text('Mangler fnr.')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    _filter == 'mangler'
                        ? 'Alle aktive ansatte har bursdag registrert.'
                        : 'Ingen bursdager i dette filteret.',
                    style: DriftProTheme.bodyMd.copyWith(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final p = r.profile;
                    final isToday = r.daysUntil == 0;

                    return Material(
                      color: isDark ? DriftProTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isToday
                              ? DriftProTheme.primaryGreen
                              : DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                          child: Icon(
                            Icons.cake_outlined,
                            color: isToday ? Colors.white : DriftProTheme.primaryGreen,
                          ),
                        ),
                        title: EmployeeDisplay.nameWithNumber(p),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (r.birthday != null)
                              Text(
                                isToday
                                    ? 'Bursdag i dag! Fyller ${r.ageNext} år'
                                    : '${r.birthday!.day.toString().padLeft(2, '0')}.${r.birthday!.month.toString().padLeft(2, '0')}. '
                                        '· om ${r.daysUntil} dager · fyller ${r.ageNext} år',
                                style: TextStyle(
                                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                                  color: isToday ? DriftProTheme.primaryGreen : null,
                                ),
                              )
                            else
                              const Text(
                                'Mangler fødselsnummer / fødselsdato',
                                style: TextStyle(color: Colors.orange),
                              ),
                            Text(
                              '${_deptName(p.departmentId)} · '
                              'fnr: ${NorwegianNationalId.formatMasked(p.nationalIdNumber)}',
                              style: DriftProTheme.caption,
                            ),
                          ],
                        ),
                        trailing: widget.canEdit
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Registrer fødselsnummer',
                                onPressed: () => _editNationalId(p),
                              )
                            : null,
                        onTap: widget.canEdit ? () => _editNationalId(p) : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
