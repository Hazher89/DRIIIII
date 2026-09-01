import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/chat/chat_advanced_service.dart';
import '../../../core/theme/app_theme.dart';

class ChatScheduleSheet extends StatefulWidget {
  const ChatScheduleSheet({super.key, required this.initialBody});

  final String initialBody;

  static Future<DateTime?> pick(BuildContext context, {String initialBody = ''}) async {
    return showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChatScheduleSheet(initialBody: initialBody),
    );
  }

  @override
  State<ChatScheduleSheet> createState() => _ChatScheduleSheetState();
}

class _ChatScheduleSheetState extends State<ChatScheduleSheet> {
  late DateTime _when;
  final _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    _when = DateTime.now().add(const Duration(hours: 1));
    _body.text = widget.initialBody;
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Planlegg melding', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat('EEEE d. MMM HH:mm', 'nb').format(_when)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _when,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d == null || !mounted) return;
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
                  if (t == null || !mounted) return;
                  setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
              ),
              TextField(controller: _body, maxLines: 3, decoration: const InputDecoration(labelText: 'Melding')),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                onPressed: () => Navigator.pop(context, _when),
                child: const Text('Bekreft tidspunkt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatTemplatesSheet extends StatelessWidget {
  const ChatTemplatesSheet({super.key, required this.templates});

  final List<ChatMessageTemplate> templates;

  static Future<ChatMessageTemplate?> pick(BuildContext context) async {
    final templates = await ChatAdvancedService.fetchTemplates();
    if (!context.mounted) return null;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen maler ennå — moderator kan legge til under rom-innstillinger.')),
      );
      return null;
    }
    return showModalBottomSheet<ChatMessageTemplate>(
      context: context,
      showDragHandle: true,
      builder: (_) => ChatTemplatesSheet(templates: templates),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Hurtigmal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ),
          for (final t in templates)
            ListTile(
              title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, t),
            ),
        ],
      ),
    );
  }
}

class ChatReportSheet extends StatefulWidget {
  const ChatReportSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (_) => const ChatReportSheet(),
    );
  }

  @override
  State<ChatReportSheet> createState() => _ChatReportSheetState();
}

class _ChatReportSheetState extends State<ChatReportSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Rapporter melding', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Beskriv problemet (valgfritt)…'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, _reason.text.trim()),
              child: const Text('Send rapport'),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatSelfDestructPicker extends StatelessWidget {
  const ChatSelfDestructPicker({super.key});

  static Future<int?> pick(BuildContext context) {
    return showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (_) => const ChatSelfDestructPicker(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Selvdestruer etter…', style: TextStyle(fontWeight: FontWeight.w900))),
          ListTile(title: const Text('Av'), onTap: () => Navigator.pop(context, null)),
          ListTile(title: const Text('1 time'), onTap: () => Navigator.pop(context, 1)),
          ListTile(title: const Text('24 timer'), onTap: () => Navigator.pop(context, 24)),
          ListTile(title: const Text('7 dager'), onTap: () => Navigator.pop(context, 168)),
        ],
      ),
    );
  }
}
