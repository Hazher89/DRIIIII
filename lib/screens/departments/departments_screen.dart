import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import 'department_details_screen.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  List<Department> _departments = [];
  Map<String, UserProfile> _leaders = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw Exception('Selskap ikke funnet');

      final departments = await SupabaseService.fetchDepartments(companyId: companyId);
      final profiles = await SupabaseService.fetchProfiles(companyId: companyId);
      
      final leaderMap = {for (var p in profiles) p.id: p};

      setState(() {
        _departments = departments;
        _leaders = leaderMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Feil ved henting av avdelinger: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Avdelinger'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.add),
            onPressed: () => _createNewDepartment(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _departments.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _departments.length,
                          itemBuilder: (context, index) {
                            final dept = _departments[index];
                            final leader = _leaders[dept.leaderId];
                            return _buildDepartmentCard(dept, leader, isDark);
                          },
                        ),
                ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.business, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Ingen avdelinger opprettet ennå',
            style: DriftProTheme.headingMd.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _createNewDepartment,
            icon: const Icon(AppIcons.add),
            label: const Text('Opprett din første avdeling'),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCard(Department dept, UserProfile? leader, bool isDark) {
    final color = _parseColor(dept.colorCode);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        boxShadow: DriftProTheme.cardShadow,
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DepartmentDetailsScreen(department: dept),
            ),
          ).then((_) => _loadData()),
          borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(DriftProTheme.radiusLg),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: color,
                      child: Icon(_getIcon(dept.iconName), color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dept.name,
                            style: DriftProTheme.headingMd.copyWith(
                              color: isDark ? Colors.white : Colors.grey[900],
                            ),
                          ),
                          if (dept.description != null && dept.description!.isNotEmpty)
                            Text(
                              dept.description!,
                              style: DriftProTheme.bodySm.copyWith(
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildCompactStat(
                      context,
                      'Leder',
                      leader?.fullName ?? 'Ikke valgt',
                      AppIcons.profile,
                      isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: DriftProTheme.primaryGreen),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: DriftProTheme.caption.copyWith(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            Text(
              value,
              style: DriftProTheme.labelMd.copyWith(
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return DriftProTheme.primaryGreen;
    }
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'business':
        return AppIcons.business;
      case 'group':
        return Icons.group;
      case 'build':
        return Icons.build;
      case 'safety':
        return Icons.security;
      default:
        return AppIcons.business;
    }
  }

  void _createNewDepartment() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return;

    final newDept = Department(
      id: '', // Will be set by Supabase
      companyId: companyId,
      name: 'Ny Avdeling',
      description: '',
      colorCode: '#2E7D32',
      iconName: 'business',
    );

    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DepartmentDetailsScreen(department: newDept, isNew: true),
      ),
    ).then((_) => _loadData());
  }
}
