import 'package:flutter/material.dart';

import '../../core/services/chat/chat_advanced_service.dart';
import '../../core/theme/app_theme.dart';

class ChatStatsScreen extends StatefulWidget {
  const ChatStatsScreen({super.key});

  @override
  State<ChatStatsScreen> createState() => _ChatStatsScreenState();
}

class _ChatStatsScreenState extends State<ChatStatsScreen> {
  Map<String, dynamic> _stats = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await ChatAdvancedService.fetchStats();
      if (mounted) setState(() => _stats = s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat-statistikk'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatCard(
                  icon: Icons.chat_bubble_outline,
                  label: 'Meldinger (30 dager)',
                  value: '${_stats['total_messages'] ?? 0}',
                  color: DriftProTheme.primaryGreen,
                ),
                _StatCard(
                  icon: Icons.forum_outlined,
                  label: 'Aktive samtaler',
                  value: '${_stats['active_rooms'] ?? 0}',
                  color: Colors.blue,
                ),
                _StatCard(
                  icon: Icons.flag_outlined,
                  label: 'Åpne rapporter',
                  value: '${_stats['open_reports'] ?? 0}',
                  color: Colors.orange,
                ),
                _StatCard(
                  icon: Icons.person_add_alt_1,
                  label: 'Venter på godkjenning',
                  value: '${_stats['pending_members'] ?? 0}',
                  color: Colors.purple,
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
        title: Text(label),
        trailing: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
      ),
    );
  }
}
