import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_icons.dart';
import '../dashboard/dashboard_screen.dart';
import '../absence/absence_screen.dart';
import '../tickets/tickets_screen.dart';
import '../hms/hms_screen.dart';
import '../surveys/survey_list_screen.dart';
import '../more/more_screen.dart';
import '../../models/user_profile.dart';
import '../../core/services/supabase_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  UserProfile? _profile;
  bool _isLoadingAccess = true;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (mounted) {
        if (profile == null || (!profile.isOnboarded) || (!profile.isApproved && profile.role != UserRole.superadmin)) {
           // Security leak detected! User is in MainShell but shouldn't be.
           debugPrint('Security fallback triggered in MainShell for user ${profile?.id}');
           // We can't easily pushReplacement here without context, but we can set state to show error
        }
        setState(() {
          _profile = profile;
          _isLoadingAccess = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAccess = false;
        });
      }
    }
  }

  void _onNavigate(int index) {
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  bool _hasAccess(String key) {
    if (_profile == null) return false; // Default to FALSE while loading
    if (_profile!.role == UserRole.superadmin) return true; // SuperAdmins bypass
    
    final settings = _profile!.accessSettings;
    if (settings == null) return true; // Default allow if no map exists
    
    return settings[key] ?? true;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAccess) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    // Safety check fallback
    if (_profile == null) {
      return const Scaffold(body: Center(child: Text('Profil ikke funnet. Prøv å logge inn på nytt.')));
    }
    
    if (!_profile!.isOnboarded) {
      // Should not happen, but safeguard
      return Scaffold(body: Center(child: TextButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Vennligst fullfør onboarding'))));
    }

    if (!_profile!.isApproved && _profile!.role != UserRole.superadmin) {
      return const Scaffold(body: Center(child: Text('Din konto venter på godkjenning.')));
    }
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allScreens = [
      {'screen': DashboardScreen(onNavigate: _onNavigate), 'icon': AppIcons.dashboard, 'label': AppStrings.navDashboard, 'access': 'dashboard'},
      {'screen': const SurveyListScreen(), 'icon': AppIcons.survey, 'label': AppStrings.navSurveys, 'access': 'surveys'},
      {'screen': const AbsenceScreen(), 'icon': AppIcons.absence, 'label': AppStrings.navAbsence, 'access': 'fravaer'},
      {'screen': const TicketsScreen(), 'icon': AppIcons.ticket, 'label': AppStrings.navTickets, 'access': 'avvik'},
      {'screen': const HmsScreen(), 'icon': AppIcons.hms, 'label': AppStrings.navHMS, 'access': 'hms'},
      {'screen': const MoreScreen(), 'icon': AppIcons.more, 'label': AppStrings.navMore, 'access': 'more'},
    ];

    // Filter screens based on access settings
    final visibleScreens = allScreens.where((s) => _hasAccess(s['access'] as String)).toList();

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex.clamp(0, visibleScreens.length - 1),
        children: visibleScreens.map((s) => s['screen'] as Widget).toList(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: visibleScreens.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return _buildNavItem(i, s['icon'] as IconData, s['label'] as String, isDark);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isDark, {int? badge}) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onNavigate(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DriftProTheme.primaryGreen.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge != null && badge > 0,
              label: badge != null ? Text('$badge', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)) : null,
              backgroundColor: DriftProTheme.error,
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? DriftProTheme.primaryGreen : (isDark ? Colors.grey[600] : Colors.grey[450]),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? DriftProTheme.primaryGreen : (isDark ? Colors.grey[600] : Colors.grey[450]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
