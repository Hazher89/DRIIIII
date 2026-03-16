import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/hms/equipment.dart';

class EquipmentRegistryScreen extends StatefulWidget {
  const EquipmentRegistryScreen({super.key});

  @override
  State<EquipmentRegistryScreen> createState() => _EquipmentRegistryScreenState();
}

class _EquipmentRegistryScreenState extends State<EquipmentRegistryScreen> {
  bool _isLoading = true;
  List<Equipment> _equipment = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) return;

      final client = SupabaseService.client;
      final response = await client
          .from('equipment')
          .select()
          .eq('company_id', companyId)
          .order('name', ascending: true);
      
      setState(() {
        _equipment = (response as List).map((e) => Equipment.fromJson(e as Map<String, dynamic>)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  List<Equipment> get _filteredEquipment {
    if (_searchQuery.isEmpty) return _equipment;
    return _equipment.where((e) {
      return e.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (e.serialNumber?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (e.brand?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Maskiner & Utstyr'),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_scanner_rounded), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(isDark),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _buildList(isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: DriftProTheme.primaryGreen,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Søk i utstyr...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildList(bool isDark) {
    final items = _filteredEquipment;
    if (items.isEmpty) return const Center(child: Text('Ingen utstyr funnet'));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildEquipmentCard(item, isDark);
      },
    );
  }

  Widget _buildEquipmentCard(Equipment item, bool isDark) {
    Color statusColor;
    switch (item.status) {
      case EquipmentStatus.ok: statusColor = DriftProTheme.success; break;
      case EquipmentStatus.needsService: statusColor = DriftProTheme.warning; break;
      case EquipmentStatus.broken: statusColor = DriftProTheme.error; break;
      case EquipmentStatus.retired: statusColor = Colors.grey; break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50, height: 50,
          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.construction_rounded, color: statusColor),
        ),
        title: Text(item.name, style: DriftProTheme.labelMd),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${item.brand ?? ""} ${item.model ?? ""}', style: DriftProTheme.bodySm),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(item.status.label, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                if (item.nextService != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.event_rounded, size: 12, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('Service: ${item.nextService!.day}.${item.nextService!.month}.${item.nextService!.year}', style: DriftProTheme.bodySm.copyWith(fontSize: 10)),
                ],
              ],
            ),
          ],
        ),
        onTap: () {},
      ),
    );
  }
}
