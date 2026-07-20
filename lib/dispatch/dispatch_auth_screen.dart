import 'package:flutter/material.dart';

import '../core/config/driftpro_client.dart';
import '../core/theme/app_theme.dart';
import '../screens/auth/auth_gate_screen.dart';

/// Innlogging for ruteplanlegger — kontoer valideres mot DriftPro (Supabase Auth).
class DispatchAuthScreen extends StatelessWidget {
  const DispatchAuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0A192F), const Color(0xFF112240)]
                : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    size: 64,
                    color: isDark ? Colors.white : DriftProTheme.primaryGreen,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    DriftProClient.displayName,
                    textAlign: TextAlign.center,
                    style: DriftProTheme.headingLg.copyWith(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    DriftProClient.tagline,
                    textAlign: TextAlign.center,
                    style: DriftProTheme.bodyMd.copyWith(
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Erstatter SAP (ordre) og TransFleet (planlegging). '
                    'Sjåfør, bedrift og MAVI-biler hentes live fra DriftPro (Supabase).',
                    textAlign: TextAlign.center,
                    style: DriftProTheme.caption.copyWith(
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 36),
                  _LoginCard(
                    icon: Icons.badge_outlined,
                    title: 'MAVI / DriftPro-ansatt',
                    subtitle: 'Ansattnummer + passord — samme konto som i DriftPro.',
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
                  _LoginCard(
                    icon: Icons.business_outlined,
                    title: 'Administrator / planlegger',
                    subtitle: 'E-post og passord for intern DriftPro-bruker med rute-tilgang.',
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
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }
}
