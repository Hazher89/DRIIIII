import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/safety_round.dart';
import 'package:uuid/uuid.dart';

class NewSafetyRoundScreen extends StatefulWidget {
  const NewSafetyRoundScreen({super.key});

  @override
  State<NewSafetyRoundScreen> createState() => _NewSafetyRoundScreenState();
}

class _NewSafetyRoundScreenState extends State<NewSafetyRoundScreen> {
  final _titleController = TextEditingController();
  DateTime _scheduledDate = DateTime.now();
  
  final List<Map<String, dynamic>> _checklist = [
    {'task': 'Nødutganger er frie og merket', 'status': 'ok'},
    {'task': 'Brannslokkingsutstyr er tilgjengelig', 'status': 'ok'},
    {'task': 'Førstehjelpsutstyr er komplett', 'status': 'ok'},
    {'task': 'Ryddighet på arbeidsplassen', 'status': 'ok'},
    {'task': 'Bruk av personlig verneutstyr', 'status': 'ok'},
    {'task': 'Elektriske anlegg og ledninger', 'status': 'ok'},
  ];
  
  final List<Map<String, dynamic>> _findings = [];
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Ny Vernerunde')),
      bottomNavigationBar: _buildBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInput('Tittel på runde', _titleController, hint: 'F.eks. Månedlig vernerunde - Januar', isDark: isDark),
            const SizedBox(height: 16),
            
            Text('Dato'.toUpperCase(), style: DriftProTheme.labelSm),
            const SizedBox(height: 8),
            _buildDatePicker(isDark),
            const SizedBox(height: 32),
            
            Text('Sjekkliste'.toUpperCase(), style: DriftProTheme.labelSm),
            const SizedBox(height: 12),
            _buildChecklist(isDark),
            const SizedBox(height: 32),
            
            _buildFindingsSection(isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, {String? hint, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DriftProTheme.labelMd),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint, fillColor: isDark ? DriftProTheme.cardDark : Colors.white),
        ),
      ],
    );
  }

  Widget _buildDatePicker(bool isDark) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: _scheduledDate, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
        if (d != null) setState(() => _scheduledDate = d);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 20, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 12),
            Text('${_scheduledDate.day}.${_scheduledDate.month}.${_scheduledDate.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklist(bool isDark) {
    return Column(
      children: _checklist.map((item) {
        final status = item['status'];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100)),
          child: ListTile(
            title: Text(item['task'], style: DriftProTheme.bodyMd),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusIcon(item, 'ok', Icons.check_circle_outline, Colors.green),
                _statusIcon(item, 'avvik', Icons.error_outline, Colors.orange),
                _statusIcon(item, 'n/a', Icons.not_interested, Colors.grey),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _statusIcon(Map<String, dynamic> item, String status, IconData icon, Color color) {
    final isSelected = item['status'] == status;
    return IconButton(
      icon: Icon(icon, color: isSelected ? color : color.withOpacity(0.2)),
      onPressed: () => setState(() => item['status'] = status),
    );
  }

  Widget _buildFindingsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Avvik / Funn'.toUpperCase(), style: DriftProTheme.labelSm),
            TextButton.icon(onPressed: _addFinding, icon: const Icon(Icons.add, size: 18), label: const Text('Legg til funn')),
          ],
        ),
        if (_findings.isEmpty) 
          const Center(child: Text('Ingen avvik registrert på runden.', style: TextStyle(fontSize: 12, color: Colors.grey)))
        else
          ..._findings.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            return ListTile(
              title: Text(f['description']),
              subtitle: Text('Alvorlighetsgrad: ${f['severity']}'),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => setState(() => _findings.removeAt(i))),
            );
          }),
      ],
    );
  }

  void _addFinding() {
    final descCtrl = TextEditingController();
    String severity = 'Middels';
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Registrer funn'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Beskrivelse av funn')),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: severity,
          items: ['Lav', 'Middels', 'Høy'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (val) => severity = val!,
          decoration: const InputDecoration(labelText: 'Alvorlighetsgrad'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('AVBRYT')),
        TextButton(onPressed: () {
          if (descCtrl.text.isNotEmpty) {
            setState(() => _findings.add({'description': descCtrl.text, 'severity': severity}));
            Navigator.pop(context);
          }
        }, child: const Text('LEGG TIL')),
      ],
    ));
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _save,
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
        child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('FULLFØR VERNERUNDE'),
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile == null) return;
      
      final round = SafetyRound(
        id: const Uuid().v4(),
        companyId: profile.companyId!,
        departmentId: profile.departmentId,
        conductedBy: profile.id,
        title: _titleController.text,
        scheduledDate: _scheduledDate,
        checklist: _checklist,
        findings: _findings,
        overallStatus: 'fullført',
        completedAt: DateTime.now(),
      );
      
      await SupabaseService.createSafetyRound(round);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
