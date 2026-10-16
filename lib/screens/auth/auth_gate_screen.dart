import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/permissions/access_session_cache.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/employee_auth_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../screens/drive_monitor/drive_monitor_kiosk_screen.dart';
import '../../widgets/auth_screen_shell.dart';

/// Første valg: ansatte (ansattnummer) eller partner (brukernavn/passord).
class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScreenShell(
      child: Column(
        children: [
          Text(
            'Logg inn',
            textAlign: TextAlign.center,
            style: authTitleStyle(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Velg konto-type for å fortsette.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context),
          ),
          const SizedBox(height: 28),
          _GateCard(
            icon: Icons.badge_outlined,
            title: 'Ansatte',
            subtitle: 'Ansattnummer og passord',
            color: DriftProTheme.primaryGreen,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EmployeeLoginScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _GateCard(
            icon: Icons.handshake_outlined,
            title: 'Partnere',
            subtitle: 'Brukernavn og passord',
            color: const Color(0xFF1565C0),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PartnerLoginScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.92);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.35 : 0.18),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.2,
                          color: isDark ? Colors.white : const Color(0xFF102A1C),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: color.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Intern innlogging — ansattnummer og passord.
class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen> {
  final _employeeNumber = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null && mounted) {
        _leaveLoginScreen();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _employeeNumber.dispose();
    _password.dispose();
    super.dispose();
  }

  void _leaveLoginScreen() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _signInWithEmployeeNumber() async {
    if (_loading) return;
    final no = _employeeNumber.text.trim();
    final pw = EmployeeAuthService.normalizePasswordForAuth(_password.text);
    if (no.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn ansattnummer og passord')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await EmployeeAuthService.signInWithEmployeeNumber(
        employeeNumber: no,
        password: pw,
      );
      await SupabaseService.ensureSessionLinkedToCompany();
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      // Alltid MAVI-modus etter ansatt-innlogging (ikke partnerportal).
      AccessSessionCache.setPartnerPortalSession(false);
      if (profile != null) {
        AccessSessionCache.setProfile(profile);
      }
      if (!mounted) return;
      if (profile?.driveMonitorDevice == true) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => DriveMonitorKioskScreen(profile: profile!),
          ),
          (_) => false,
        );
        return;
      }
      // Alltid ansatt-dashboard — ignorer gammel returnTo=/portal fra partner.
      context.go(AppPaths.dashboard);
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty
                  ? e.message
                  : 'Feil ansattnummer eller passord.',
            ),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenShell(
      showBack: true,
      child: Column(
        children: [
          Text('Ansatte', style: authTitleStyle(context)),
          const SizedBox(height: 8),
          Text(
            'Logg inn med ansattnummer og passord.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _employeeNumber,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Ansattnummer',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Passord',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _signInWithEmployeeNumber(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _signInWithEmployeeNumber,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Logg inn',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Partner: e-post/brukernavn + passord, eller magic link.
class PartnerLoginScreen extends StatefulWidget {
  const PartnerLoginScreen({super.key});

  @override
  State<PartnerLoginScreen> createState() => _PartnerLoginScreenState();
}

class _PartnerLoginScreenState extends State<PartnerLoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null && mounted) {
        _completePartnerLogin();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _completePartnerLogin() {
    if (!mounted) return;
    // Marker partner-sesjon før redirect — også når Auth-e-post ikke er @portal.driftpro.no.
    AccessSessionCache.setPartnerPortalSession(true);
    context.go(AppPaths.portal);
  }

  Future<String?> _resolveLoginEmail(String identifier) async {
    try {
      return await PartnerService.resolveLoginIdentifierToEmail(identifier);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: DriftProTheme.error),
        );
      }
      return null;
    }
  }

  Future<void> _signIn() async {
    if (_loading) return;
    if (!SupabaseService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appen er ikke koblet til server. Last siden på nytt (Ctrl+F5).'),
          backgroundColor: DriftProTheme.error,
        ),
      );
      return;
    }
    final identifier = _identifier.text.trim();
    final pw = EmployeeAuthService.normalizePasswordForAuth(_password.text);
    if (identifier.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll inn brukernavn og passord')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final email = await _resolveLoginEmail(identifier);
      if (email == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Fant ikke brukernavn «$identifier». Sjekk staving eller bruk «Glemt passord?».',
              ),
              backgroundColor: DriftProTheme.error,
            ),
          );
        }
        return;
      }
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pw,
      );
      await SupabaseService.ensureSessionLinkedToCompany();
      if (!mounted) return;
      _completePartnerLogin();
    } on AuthException catch (e) {
      if (mounted) {
        final msg = e.message.toLowerCase();
        final hint = msg.contains('invalid') || msg.contains('credentials')
            ? 'Feil brukernavn eller passord. Prøv «Glemt passord?» for nytt passord på SMS.'
            : (e.message.isNotEmpty ? e.message : 'Innlogging feilet');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hint), backgroundColor: DriftProTheme.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Innlogging feilet: $e'), backgroundColor: DriftProTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_loading) return;
    final usernameCtrl = TextEditingController(text: _identifier.text.trim());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Glemt passord?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skriv brukernavnet ditt (fra SMS fra MAVI). Du får nytt passord på SMS. '
              'Det gamle passordet slutter å virke med én gang.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Brukernavn',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send nytt passord på SMS'),
          ),
        ],
      ),
    );
    final username = usernameCtrl.text.trim();
    usernameCtrl.dispose();
    if (confirmed != true || username.isEmpty) return;

    setState(() => _loading = true);
    try {
      final result = await PartnerService.resetPortalPasswordByUsername(username);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? (result.message ?? 'Nytt passord sendt på SMS.')
                : (result.error ?? 'Kunne ikke tilbakestille passord'),
          ),
          backgroundColor: result.success ? Colors.green : DriftProTheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScreenShell(
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Partnere', style: authTitleStyle(context)),
          const SizedBox(height: 8),
          Text(
            'Bil-eier, sjåfør og partneransatte — brukernavn og passord.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _identifier,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Brukernavn',
              hintText: 'f.eks. eierhaz8382, m71 eller a…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Passord',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _forgotPassword,
              child: const Text('Glemt passord?'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : () => _signIn(),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF1565C0),
            ),
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Logg inn'),
          ),
          const SizedBox(height: 16),
          Text(
            'Har du glemt passordet, trykk «Glemt passord?»',
            textAlign: TextAlign.center,
            style: authMutedStyle(context, size: 12),
          ),
        ],
      ),
    );
  }
}
