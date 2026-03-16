import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/sja_form.dart';
import 'package:uuid/uuid.dart';

class NewSjaScreen extends StatefulWidget {
  const NewSjaScreen({super.key});

  @override
  State<NewSjaScreen> createState() => _NewSjaScreenState();
}

class _NewSjaScreenState extends State<NewSjaScreen> {
  final _titleController = TextEditingController();
  final _workDescController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime _plannedDate = DateTime.now();
  
  final List<Map<String, dynamic>> _hazards = [];
  final List<String> _selectedPpe = [];
  
  bool _isSubmitting = false;

  final List<String> _ppeOptions = [
    'Hjelm', 'Verneskog', 'Hansker', 'Hørselsvern', 'Øyebeskyttelse', 'Andedrettsvern', 'Fallsikring', 'Synlighetsbekledning'
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Ny SJA')),
      bottomNavigationBar: _buildBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInput('Tittel på arbeid', _titleController, hint: 'F.eks. Skifte av vinduer i 4. etasje', isDark: isDark),
            const SizedBox(height: 16),
            _buildInput('Arbeidsbeskrivelse', _workDescController, maxLines: 3, hint: 'Beskriv arbeidet som skal utføres...', isDark: isDark),
            const SizedBox(height: 16),
            _buildInput('Lokasjon', _locationController, hint: 'F.eks. Hovedinngang eller Prosjekt X', isDark: isDark),
            const SizedBox(height: 24),
            
            Text('Dato for arbeid'.toUpperCase(), style: DriftProTheme.labelSm),
            const SizedBox(height: 8),
            _buildDatePicker(isDark),
            const SizedBox(height: 32),
            
            _buildPpeSection(isDark),
            const SizedBox(height: 32),
            
            _buildHazardsSection(isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, {String? hint, int maxLines = 1, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DriftProTheme.labelMd),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint, fillColor: isDark ? DriftProTheme.cardDark : Colors.white),
        ),
      ],
    );
  }

  Widget _buildDatePicker(bool isDark) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: _plannedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
        if (d != null) setState(() => _plannedDate = d);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 20, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 12),
            Text('${_plannedDate.day}.${_plannedDate.month}.${_plannedDate.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildPpeSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Påkrevd verneutstyr'.toUpperCase(), style: DriftProTheme.labelSm),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _ppeOptions.map<Widget>((ppe) {
            final isSelected = _selectedPpe.contains(ppe);
            return ChoiceChip(
              label: Text(ppe),
              selected: isSelected,
              onSelected: (val) {
                setState(() { if (val) _selectedPpe.add(ppe); else _selectedPpe.remove(ppe); });
              },
              selectedColor: DriftProTheme.primaryGreen,
              labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHazardsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Risikomomenter'.toUpperCase(), style: DriftProTheme.labelSm),
            TextButton.icon(onPressed: _addHazard, icon: const Icon(Icons.add, size: 18), label: const Text('Legg til')),
          ],
        ),
        const SizedBox(height: 8),
        if (_hazards.isEmpty) 
          const Center(child: Text('Ingen risikomomenter lagt til ennå.', style: TextStyle(fontSize: 12, color: Colors.grey)))
        else
          ..._hazards.asMap().entries.map((entry) {
            final i = entry.key;
            final h = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Fare: ${h['hazard']}', style: const TextStyle(fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () => setState(() => _hazards.removeAt(i)))]),
                  Text('Tiltak: ${h['measure']}', style: DriftProTheme.bodySm),
                ],
              ),
            );
          }),
      ],
    );
  }

  void _addHazard() {
    final hazardCtrl = TextEditingController();
    final measureCtrl = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('Ny fare'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: hazardCtrl, decoration: const InputDecoration(labelText: 'Hva er faren?')),
        TextField(controller: measureCtrl, decoration: const InputDecoration(labelText: 'Hva er tiltaket?')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('AVBRYT')),
        TextButton(onPressed: () {
          if (hazardCtrl.text.isNotEmpty && measureCtrl.text.isNotEmpty) {
            setState(() => _hazards.add({'hazard': hazardCtrl.text, 'measure': measureCtrl.text}));
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
        child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('SEND INN SJA'),
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile == null) return;
      
      final sja = SjaForm(
        id: const Uuid().v4(),
        companyId: profile.companyId!,
        departmentId: profile.departmentId,
        createdBy: profile.id,
        title: _titleController.text,
        workDescription: _workDescController.text,
        location: _locationController.text,
        plannedDate: _plannedDate,
        status: SjaStatus.utkast,
        hazards: _hazards,
        measures: [], // redundant with hazards list for now
        requiredPpe: _selectedPpe,
      );
      
      await SupabaseService.createSjaForm(sja);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
