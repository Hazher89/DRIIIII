import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import 'widgets/employee_files_panel.dart';

/// Personalmappe — ansatt ser egne filer (der superadmin har gitt tilgang).
class EmployeePersonalFolderScreen extends StatefulWidget {
  const EmployeePersonalFolderScreen({super.key});

  @override
  State<EmployeePersonalFolderScreen> createState() =>
      _EmployeePersonalFolderScreenState();
}

class _EmployeePersonalFolderScreenState
    extends State<EmployeePersonalFolderScreen> {
  UserProfile? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SupabaseService.fetchCurrentUserProfile();
    if (mounted) setState(() => _me = p);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (me == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalmappe'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Her ser du dokumenter, kursbevis og bilder som bedriften har delt med deg. '
              'Kontakt leder hvis noe mangler.',
            ),
          ),
          Expanded(
            child: EmployeeFilesPanel(
              employee: me,
              currentUser: me,
              canUpload: false,
              canManageVisibility: false,
            ),
          ),
        ],
      ),
    );
  }
}
