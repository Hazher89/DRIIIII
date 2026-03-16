import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_icons.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  AppIcons.hms,
                  size: 80,
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Venter på godkjenning',
                style: DriftProTheme.headingLg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Din profil er nå sendt til administrator for godkjenning. Du vil få tilgang til systemet så snart kontoen din er bekreftet.',
                style: DriftProTheme.bodyMd.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.1),
                    foregroundColor: Colors.red,
                    elevation: 0,
                  ),
                  child: const Text('Logg ut'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
