import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/permissions/user_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/portal_credentials.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/partner_links.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Superadmin: raskt opprette samarbeidspartner + eier-portal med valgfritt brukernavn/passord (test).
class CreateTestPartnerScreen extends StatefulWidget {
  const CreateTestPartnerScreen({super.key});

  @override
  State<CreateTestPartnerScreen> createState() => _CreateTestPartnerScreenState();
}

class _CreateTestPartnerScreenState extends State<CreateTestPartnerScreen> {
  final _orgNameCtrl = TextEditingController();
  final _orgNumberCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(text: '40000000');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  PortalProvisionResult? _result;

  @override
  void dispose() {
    _orgNameCtrl.dispose();
    _orgNumberCtrl.dispose();
    _phoneCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _orgNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final username = _usernameCtrl.text.trim().toLowerCase();
    final password = _passwordCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Organisasjonsnavn er påkrevd.');
      return;
    }
    if (phone.replaceAll(RegExp(r'\D'), '').length < 8) {
      setState(() => _error = 'Oppgi gyldig mobilnummer (8 siffer).');
      return;
    }
    if (username.length < 3) {
      setState(() => _error = 'Brukernavn må være minst 3 tegn.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Passord må være minst 6 tegn.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });

    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      if (profile == null || !profile.isSuperAdmin) {
        throw StateError('Kun superadmin kan opprette test-partnere.');
      }
      final cid = profile.companyId ?? await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw StateError('Mangler company_id');

      final orgTrim = _orgNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
      final partner = await PartnerService.createPartner(
        Partner(
          id: '',
          companyId: cid,
          orgNumber: orgTrim.isEmpty ? null : orgTrim,
          name: name,
          ownerName: name,
          phone: phone,
          country: 'NO',
          notes: 'Test-partner opprettet av superadmin',
          createdAt: DateTime.now(),
        ),
      );

      final provision = await PartnerService.provisionOwnerPortal(
        partnerId: partner.id,
        companyId: cid,
        phone: phone,
        partnerName: name,
        orgNumber: orgTrim.isEmpty ? null : orgTrim,
        ownerDisplayName: name,
        usernameOverride: username,
        passwordOverride: password,
        sendCredentialsSms: false,
      );

      if (!mounted) return;
      setState(() {
        _result = provision;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Test-partner + portalbruker')),
      body: _saving
          ? const DriftProLoadingCenter()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Opprett organisasjon og eier-innlogging med brukernavn/passord du velger. '
                  'Samme portal-layout som andre samarbeidspartnere.',
                  style: DriftProTheme.bodySm,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _orgNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Organisasjonsnavn *',
                    hintText: 'f.eks. Test Transport AS',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _orgNumberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Organisasjonsnummer',
                    hintText: '9 siffer (valgfritt)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mobil (til portal-konto) *',
                    hintText: '8 siffer, f.eks. 40000001',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                Text('Innlogging', style: DriftProTheme.labelLg),
                const SizedBox(height: 8),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Brukernavn *',
                    hintText: 'f.eks. testpartner',
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Passord *',
                    hintText: 'Minst 6 tegn',
                  ),
                  obscureText: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: DriftProTheme.error)),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DriftProTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: DriftProTheme.success.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Opprettet', style: DriftProTheme.labelLg),
                        const SizedBox(height: 8),
                        SelectableText(
                          PortalCredentials.displayLoginHint(
                            username: _result!.username,
                            password: _result!.password,
                            isOwner: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text:
                                    'Brukernavn: ${_result!.username}\nPassord: ${_result!.password}',
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kopiert')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Kopier innlogging'),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    _result == null ? 'Opprett partner + bruker' : 'Opprett ny',
                  ),
                ),
                const SizedBox(height: 12),
                if (_result != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Ferdig — tilbake til Partnere'),
                  ),
              ],
            ),
    );
  }
}
