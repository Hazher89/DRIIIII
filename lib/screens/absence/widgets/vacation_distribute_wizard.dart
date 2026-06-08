import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/absence/vacation_admin_service.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Enkel veiviser: velg hvem → hvor mange dager → bekreft.
class VacationDistributeWizard extends StatefulWidget {
  final String companyId;
  final int year;
  final List<EmployeeVacationOverview> allEmployees;
  final List<String>? preselectedUserIds;

  const VacationDistributeWizard({
    super.key,
    required this.companyId,
    required this.year,
    required this.allEmployees,
    this.preselectedUserIds,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String companyId,
    required int year,
    required List<EmployeeVacationOverview> allEmployees,
    List<String>? preselectedUserIds,
    bool selectEveryone = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => VacationDistributeWizard(
        companyId: companyId,
        year: year,
        allEmployees: allEmployees,
        preselectedUserIds: selectEveryone
            ? allEmployees.map((e) => e.employee.id).toList()
            : preselectedUserIds,
      ),
    );
  }

  @override
  State<VacationDistributeWizard> createState() => _VacationDistributeWizardState();
}

class _VacationDistributeWizardState extends State<VacationDistributeWizard> {
  int _step = 0;
  final Set<String> _selectedIds = {};
  int _days = LeaveRules.ferieLegalMinimumDays;
  int _carryover = 0;
  bool _editCarryover = false;
  bool _saving = false;
  late final TextEditingController _daysCtrl;
  late final TextEditingController _carryCtrl;

  @override
  void initState() {
    super.initState();
    _daysCtrl = TextEditingController(text: '$_days');
    _carryCtrl = TextEditingController(text: '0');
    if (widget.preselectedUserIds != null) {
      _selectedIds.addAll(widget.preselectedUserIds!);
      if (_selectedIds.isNotEmpty) {
        _step = 1;
      }
    }
  }

  @override
  void dispose() {
    _daysCtrl.dispose();
    _carryCtrl.dispose();
    super.dispose();
  }

  List<EmployeeVacationOverview> get _selectedEmployees => widget.allEmployees
      .where((e) => _selectedIds.contains(e.employee.id))
      .toList();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (_, scroll) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Del ut feriedager · ${widget.year}',
                        style: DriftProTheme.headingSm,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              _stepIndicator(),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _step == 0
                      ? _stepWho()
                      : _step == 1
                          ? _stepHowMany()
                          : _stepConfirm(),
                ),
              ),
              _bottomBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _stepIndicator() {
    const labels = ['1. Velg ansatte', '2. Antall dager', '3. Bekreft'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: List.generate(3, (i) {
          final active = i <= _step;
          return Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? DriftProTheme.primaryGreen
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: i == _step ? FontWeight.bold : FontWeight.normal,
                    color: i == _step ? DriftProTheme.primaryGreen : Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _stepWho() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hvem skal få feriedager?',
          style: DriftProTheme.labelLg,
        ),
        const SizedBox(height: 8),
        Text(
          'Kryss av én eller flere. Du kan også velge alle på én gang.',
          style: DriftProTheme.bodySm,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              if (_selectedIds.length == widget.allEmployees.length) {
                _selectedIds.clear();
              } else {
                _selectedIds.addAll(widget.allEmployees.map((e) => e.employee.id));
              }
            });
          },
          icon: Icon(
            _selectedIds.length == widget.allEmployees.length
                ? Icons.deselect
                : Icons.select_all,
          ),
          label: Text(
            _selectedIds.length == widget.allEmployees.length
                ? 'Fjern alle (${widget.allEmployees.length})'
                : 'Velg alle ${widget.allEmployees.length} ansatte',
          ),
        ),
        const SizedBox(height: 12),
        ...widget.allEmployees.map((o) {
          final q = o.quotaFor(widget.year);
          final selected = _selectedIds.contains(o.employee.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: selected
                ? DriftProTheme.primaryGreen.withValues(alpha: 0.08)
                : null,
            child: CheckboxListTile(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedIds.add(o.employee.id);
                  } else {
                    _selectedIds.remove(o.employee.id);
                  }
                });
              },
              title: Text(o.employee.fullName, style: DriftProTheme.labelMd),
              subtitle: Text(
                q == null
                    ? 'Har ikke feriedager for ${widget.year} ennå'
                    : 'Har ${q.vacationDaysRemaining} dager igjen av ${q.totalVacationDays}',
              ),
              secondary: CircleAvatar(
                child: Text(o.employee.initials, style: const TextStyle(fontSize: 12)),
              ),
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stepHowMany() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hvor mange feriedager?', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        Text(
          'Gjelder ${_selectedIds.length} ansatt${_selectedIds.length == 1 ? '' : 'e'} for ${widget.year}.',
          style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Text('Vanlige valg', style: DriftProTheme.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [20, 25, 30, 35, 40].map((d) {
            final selected = _days == d;
            return ChoiceChip(
              label: Text('$d dager', style: const TextStyle(fontSize: 15)),
              selected: selected,
              onSelected: (_) => setState(() {
                _days = d;
                _daysCtrl.text = '$d';
              }),
              selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _daysCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Eller skriv antall dager',
            border: OutlineInputBorder(),
            suffixText: 'dager',
          ),
          onChanged: (v) {
            final d = int.tryParse(v);
            if (d != null && d > 0) setState(() => _days = d);
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Juster overført fra i fjor'),
          subtitle: const Text('Kun når du tildeler én og én ansatt med egne tall'),
          value: _editCarryover,
          onChanged: (v) => setState(() => _editCarryover = v),
        ),
        if (_editCarryover && _selectedIds.length == 1) ...[
          TextField(
            controller: _carryCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Overført fra forrige år',
              border: OutlineInputBorder(),
              suffixText: 'dager',
            ),
            onChanged: (v) => _carryover = int.tryParse(v) ?? 0,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stepConfirm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bekreft', style: DriftProTheme.labelLg),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text('$_days', style: DriftProTheme.headingXl.copyWith(fontSize: 48, color: DriftProTheme.primaryGreen)),
              Text('feriedager per ansatt', style: DriftProTheme.bodyMd),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _confirmRow('År', '${widget.year}'),
              _confirmRow('Antall ansatte', '${_selectedIds.length}'),
              _confirmRow('Totalt tildelt', '${_days * _selectedIds.length} dager'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_selectedIds.length <= 5)
          ..._selectedEmployees.map(
            (e) => ListTile(
              leading: CircleAvatar(child: Text(e.employee.initials)),
              title: Text(e.employee.fullName),
              trailing: Text('$_days d', style: DriftProTheme.labelMd),
            ),
          )
        else
          Text(
            '${_selectedEmployees.take(3).map((e) => e.employee.fullName.split(' ').first).join(', ')} '
            'og ${_selectedIds.length - 3} til…',
            style: DriftProTheme.bodySm,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: DriftProTheme.bodySm),
          Text(value, style: DriftProTheme.labelMd),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _step--),
              child: const Text('Tilbake'),
            ),
          const Spacer(),
          FilledButton(
            onPressed: _saving ? null : _onPrimary,
            child: _saving
                ? SizedBox(width: 22, height: 22, child: DriftProLoadingIndicator(size: 22))
                : Text(_step < 2 ? 'Neste' : 'Bekreft og lagre'),
          ),
        ],
      ),
    );
  }

  void _onPrimary() {
    if (_step == 0) {
      if (_selectedIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Velg minst én ansatt')),
        );
        return;
      }
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      setState(() => _step = 2);
      return;
    }
    _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_selectedIds.length == widget.allEmployees.length &&
          !_editCarryover) {
        await SupabaseService.distributeVacationDays(
          companyId: widget.companyId,
          year: widget.year,
          days: _days,
        );
      } else {
        for (final id in _selectedIds) {
          await SupabaseService.upsertAbsenceQuota(
            userId: id,
            companyId: widget.companyId,
            year: widget.year,
            vacationDaysTotal: _days,
            vacationDaysCarriedOver:
                _editCarryover && _selectedIds.length == 1 ? _carryover : null,
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: DriftProTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
