import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/employee_oauth_sign_in.dart';
import '../../core/services/employee_auth_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';

/// Første valg: MAVI-ansatte (OAuth) eller samarbeidspartner (brukernavn/passord).
class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF03080F), const Color(0xFF0A192F), const Color(0xFF112240)]
                      : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9), const Color(0xFFA5D6A7)],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 56,
                      color: isDark ? Colors.white : DriftProTheme.primaryGreen,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'DriftPro',
                      style: DriftProTheme.headingLg.copyWith(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Velg hvordan du logger inn',
                      style: DriftProTheme.bodyMd.copyWith(
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 40),
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
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 32),
                    Text(
                      'Eksterne partnere får ikke tilgang til interne moduler før konto er knyttet.',
                      textAlign: TextAlign.center,
                      style: DriftProTheme.caption.copyWith(
                        color: isDark ? Colors.white38 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

/// Intern innlogging — Google og Apple (Supabase OAuth).
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
                  : 'Feil ansattnummer eller passord. Standard ved første gangs innlogging er ${EmployeeAuthService.defaultPasswordHint}.',
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
            content: Text('Kunne ikke åpne innlogging. Prøv igjen eller sjekk popup-blokkering.'),
            backgroundColor: DriftProTheme.error,
          ),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('MAVI ansatte'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'MAVI ansatte',
                  style: DriftProTheme.headingMd.copyWith(
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Logg inn med ansattnummer. Standardpassord: ${EmployeeAuthService.defaultPasswordHint} '
                  '(fire nuller — lagres som 000000 i systemet). Endre under Profil etter innlogging.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[700],
                    height: 1.35,
                  ),
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
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Logg inn', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(color: isDark ? Colors.white24 : Colors.grey[400])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'eller',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600]),
                      ),
                    ),
                    Expanded(child: Divider(color: isDark ? Colors.white24 : Colors.grey[400])),
                  ],
                ),
                const SizedBox(height: 24),
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
                const SizedBox(height: 24),
                Text(
                  'Du sendes videre til Google eller Apple for å velge konto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sesjonen er knyttet til din bedrifts tilgangsstyring.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
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
        _leaveLoginScreen();
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

  void _leaveLoginScreen() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
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
      _leaveLoginScreen();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Samarbeidspartner'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Logg inn med kontoen bedriften din har fått',
                  style: DriftProTheme.bodyMd.copyWith(
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Logg inn'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bruk brukernavn og passord fra SMS når MAVI oppretter kontoen din. '
                  'Har du glemt passordet, trykk «Glemt passord?» — nytt passord sendes på SMS.',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey[600], height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
