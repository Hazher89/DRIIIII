import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/employee_oauth_sign_in.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/employee_auth_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/auth_screen_shell.dart';

/// Første valg: MAVI-ansatte (ansattnummer) eller samarbeidspartner (brukernavn/passord).
class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScreenShell(
      child: Column(
        children: [
          Text(
            'Velg hvordan du logger inn',
            textAlign: TextAlign.center,
            style: authTitleStyle(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Én plattform for ansatte og samarbeidspartnere.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context),
          ),
          const SizedBox(height: 28),
          _GateCard(
            icon: Icons.groups_rounded,
            title: 'MAVI ansatte',
            subtitle: 'Ansattnummer + passord, eller Google / Apple.',
            color: DriftProTheme.primaryGreen,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EmployeeLoginScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _GateCard(
            icon: Icons.handshake_outlined,
            title: 'Samarbeidspartner',
            subtitle: 'Bil-eier og sjåfør: brukernavn og passord fra MAVI (SMS).',
            color: const Color(0xFF1565C0),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PartnerLoginScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Eksterne partnere får ikke tilgang til interne moduler før konto er knyttet.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context, size: 12),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(DriftProTheme.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.85),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.grey[700],
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Intern innlogging — ansattnummer, Google eller Apple.
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
    final pw = _password.text;
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
      if (mounted) _leaveLoginScreen();
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

  Future<void> _oauth(OAuthProvider provider) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final launched = await startEmployeeOAuthSignIn(provider);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kunne ikke åpne innlogging. Prøv igjen eller sjekk popup-blokkering.',
            ),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Innlogging feilet: $e'),
            backgroundColor: DriftProTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AuthScreenShell(
      showBack: true,
      child: Column(
        children: [
          Text('MAVI ansatte', style: authTitleStyle(context)),
          const SizedBox(height: 8),
          Text(
            'Logg inn med ansattnummer, eller fortsett med Google/Apple. '
            'Nye kontoer får standard ansatt-tilgang.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context, size: 12),
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
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Divider(color: isDark ? Colors.white24 : Colors.black12),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('eller', style: authMutedStyle(context, size: 12)),
              ),
              Expanded(
                child: Divider(color: isDark ? Colors.white24 : Colors.black12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AuthButton(
            loading: _loading,
            onTap: () => _oauth(OAuthProvider.google),
            background: isDark ? Colors.white : Colors.grey[900]!,
            foreground: isDark ? Colors.black : Colors.white,
            icon: Icons.g_mobiledata_rounded,
            label: 'Fortsett med Google',
          ),
          const SizedBox(height: 12),
          _AuthButton(
            loading: _loading,
            onTap: () => _oauth(OAuthProvider.apple),
            background: Colors.black,
            foreground: Colors.white,
            icon: Icons.apple,
            label: 'Fortsett med Apple',
          ),
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final IconData icon;
  final String label;

  const _AuthButton({
    required this.loading,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: loading
                ? Center(
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: foreground, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
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
    final pw = _password.text;
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
          Text('Samarbeidspartner', style: authTitleStyle(context)),
          const SizedBox(height: 8),
          Text(
            'Logg inn med kontoen bedriften din har fått',
            textAlign: TextAlign.center,
            style: authMutedStyle(context),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _identifier,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Brukernavn',
              hintText: 'f.eks. eierhaz8382 eller m71',
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
            'Bruk brukernavn og passord fra SMS når MAVI oppretter kontoen din. '
            'Har du glemt passordet, trykk «Glemt passord?» — nytt passord sendes på SMS.',
            textAlign: TextAlign.center,
            style: authMutedStyle(context, size: 12),
          ),
        ],
      ),
    );
  }
}
