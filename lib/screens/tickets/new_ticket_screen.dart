import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';

class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();

  TicketSeverity _severity = TicketSeverity.middels;
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Du må være logget inn for å registrere avvik.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        throw StateError(
          'Fant ikke selskap for brukeren. Sjekk at profile.company_id er satt.',
        );
      }

      final ticket = Ticket(
        id: 'temp', // blir erstattet av Supabase ved insert
        companyId: companyId,
        reportedBy: user.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
        severity: _severity,
        isAnonymous: _isAnonymous,
        imageUrls: const [],
        annotatedImageUrls: const [],
      );

      await SupabaseService.createTicket(ticket);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Kunne ikke lagre avvik. Prøv igjen.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.newTicket),
      ),
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ticketTitle,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ticketDescription,
                ),
                maxLines: 4,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ticketCategory,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.severity,
                style: DriftProTheme.labelLg,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TicketSeverity.values.map((s) {
                  final selected = s == _severity;
                  return ChoiceChip(
                    label: Text(s.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _severity = s);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                title: const Text(AppStrings.anonymous),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: DriftProTheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(AppStrings.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

