import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/absence/vacation_admin_service.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Enkel veiviser: velg hvem → hvor mange dager (+ restferie) → bekreft.
class VacationDistributeWizard extends StatefulWidget {
  final String companyId;
  final int year;
  final List<EmployeeVacationOverview> allEmployees;
  final List<String>? preselectedUserIds;
  final int maxCarryover;
  final bool includePriorRestDefault;

  const VacationDistributeWizard({
    super.key,
    required this.companyId,
    required this.year,
    required this.allEmployees,
    this.preselectedUserIds,
    this.maxCarryover = LeaveRules.defaultMaxCarryoverDays,
    this.includePriorRestDefault = true,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String companyId,
    required int year,
    required List<EmployeeVacationOverview> allEmployees,
    List<String>? preselectedUserIds,
    bool selectEveryone = false,
    int maxCarryover = LeaveRules.defaultMaxCarryoverDays,
    bool includePriorRestDefault = true,
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
        maxCarryover: maxCarryover,
        includePriorRestDefault: includePriorRestDefault,
        preselectedUserIds: selectEveryone
            ? allEmployees.map((e) => e.employee.id).toList()
            : preselectedUserIds,
      ),
    );
  }

  @override
  State<VacationDistributeWizard> createState() =>
      _VacationDistributeWizardState();
}

class _VacationDistributeWizardState extends State<VacationDistributeWizard> {
  int _step = 0;
  final Set<String> _selectedIds = {};
  int _days = LeaveRules.ferieLegalMinimumDays;
  bool _includePriorRest = true;
  bool _saving = false;
  late final TextEditingController _daysCtrl;

  @override
  void initState() {
    super.initState();
    _daysCtrl = TextEditingController(text: '$_days');
    _includePriorRest = widget.includePriorRestDefault;
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
    super.dispose();
  }

  List<EmployeeVacationOverview> get _selectedEmployees => widget.allEmployees
      .where((e) => _selectedIds.contains(e.employee.id))
      .toList();

  int get _priorYear => widget.year - 1;

  int _restFromPrior(EmployeeVacationOverview e) {
    if (!_includePriorRest) return 0;
    return e.carryoverEligibleFor(_priorYear, widget.maxCarryover);
  }

  int _totalFor(EmployeeVacationOverview e) => _days + _restFromPrior(e);

  int get _totalRestIncluded =>
      _selectedEmployees.fold(0, (sum, e) => sum + _restFromPrior(e));

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (_, scroll) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                        'Del ut ferie · ${widget.year}',
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
        Text('Hvem skal få feriedager?', style: DriftProTheme.labelLg),
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
                _selectedIds
                    .addAll(widget.allEmployees.map((e) => e.employee.id));
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
          final rest = o.carryoverEligibleFor(_priorYear, widget.maxCarryover);
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
                [
                  q == null
                      ? 'Ingen tildeling for ${widget.year} ennå'
                      : '${q.vacationDaysRemaining} dager igjen av ${q.totalVacationDays}',
                  if (rest > 0) 'Restferie $_priorYear: $rest d',
                ].join(' · '),
              ),
              secondary: CircleAvatar(
                child: Text(
                  o.employee.initials,
                  style: const TextStyle(fontSize: 12),
                ),
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
        Text('Hvor mange nye feriedager?', style: DriftProTheme.labelLg),
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
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.3),
            ),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Ta med restferie fra $_priorYear',
              style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Systemet husker ubrukte dager fra i fjor (maks ${widget.maxCarryover} d/pers) '
              'og legger dem til for ${widget.year}.',
              style: DriftProTheme.caption,
            ),
            value: _includePriorRest,
            onChanged: (v) => setState(() => _includePriorRest = v),
          ),
        ),
        if (_includePriorRest) ...[
          const SizedBox(height: 12),
          Text(
            '$_totalRestIncluded dager restferie fordeles automatisk blant de valgte.',
            style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w700),
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
            border: Border.all(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Text(
                '$_days',
                style: DriftProTheme.headingXl.copyWith(
                  fontSize: 48,
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              Text('nye feriedager per ansatt', style: DriftProTheme.bodyMd),
              if (_includePriorRest) ...[
                const SizedBox(height: 8),
                Text(
                  '+ restferie fra $_priorYear (individuelt)',
                  style: DriftProTheme.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DriftProTheme.primaryGreen,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _confirmRow('År', '${widget.year}'),
              _confirmRow('Antall ansatte', '${_selectedIds.length}'),
              _confirmRow(
                'Nye dager totalt',
                '${_days * _selectedIds.length} dager',
              ),
              if (_includePriorRest)
                _confirmRow('Restferie totalt', '$_totalRestIncluded dager'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._selectedEmployees.take(12).map((e) {
          final rest = _restFromPrior(e);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(e.employee.initials)),
            title: Text(e.employee.fullName),
            subtitle: rest > 0
                ? Text('$_days nye + $rest rest = ${_totalFor(e)} d totalt')
                : Text('$_days dager'),
            trailing: Text(
              '${_totalFor(e)} d',
              style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
            ),
          );
        }),
        if (_selectedEmployees.length > 12)
          Text(
            '… og ${_selectedEmployees.length - 12} til',
            style: DriftProTheme.caption,
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
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: DriftProLoadingIndicator(size: 22),
                  )
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
      for (final e in _selectedEmployees) {
        final rest = _restFromPrior(e);
        await SupabaseService.upsertAbsenceQuota(
          userId: e.employee.id,
          companyId: widget.companyId,
          year: widget.year,
          vacationDaysTotal: _days,
          vacationDaysCarriedOver: rest,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke lagre: $e'),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
