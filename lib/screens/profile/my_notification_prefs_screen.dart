import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/permissions/notification_event_access.dart';
import '../../core/permissions/user_access.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import 'widgets/notification_tri_channel_picker.dart';

class _PrefEvent {
  _PrefEvent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.sms,
    required this.email,
    required this.push,
  });

  final String id;
  final String title;
  final String subtitle;
  final String category;
  bool sms;
  bool email;
  bool push;

  factory _PrefEvent.fromJson(Map<String, dynamic> json) {
    return _PrefEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      category: json['category'] as String? ?? 'Varsler',
      sms: json['sms'] as bool? ?? true,
      email: json['email'] as bool? ?? true,
      push: json['push'] as bool? ?? true,
    );
  }
}

/// Personlige varselkanaler. Alle innloggede brukere.
class MyNotificationPrefsScreen extends StatefulWidget {
  const MyNotificationPrefsScreen({super.key});

  @override
  State<MyNotificationPrefsScreen> createState() =>
      _MyNotificationPrefsScreenState();
}

class _MyNotificationPrefsScreenState extends State<MyNotificationPrefsScreen> {
  final _search = TextEditingController();
  List<_PrefEvent> _events = [];
  bool _loading = true;
  String? _error;
  String? _savingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_my_notification_preferences',
      );
      final map = Map<String, dynamic>.from(raw as Map);
      final uid = Supabase.instance.client.auth.currentUser?.id;
      UserProfile? profile;
      var departmentLeader = false;
      if (uid != null) {
        final row = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', uid)
            .maybeSingle();
        if (row != null) {
          profile = UserProfile.fromJson(Map<String, dynamic>.from(row));
        }
        try {
          final leaders = await Supabase.instance.client
              .from('department_leaders')
              .select('profile_id')
              .eq('profile_id', uid)
              .limit(1);
          departmentLeader = (leaders as List).isNotEmpty;
        } catch (_) {}
      }
      final access = profile?.access;
      final list = (map['events'] as List? ?? [])
          .map((e) => _PrefEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((e) => e.id.isNotEmpty)
          .where((e) {
            if (profile == null || access == null) return false;
            return NotificationEventAccess.visible(
              access: access,
              profile: profile,
              eventId: e.id,
              departmentLeader: departmentLeader,
            );
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _events = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kunne ikke hente varslene. Prøv igjen om litt.';
      });
    }
  }

  Future<void> _save(_PrefEvent event) async {
    setState(() => _savingId = event.id);
    try {
      await Supabase.instance.client.rpc(
        'set_my_notification_preference',
        params: {
          'p_event_id': event.id,
          'p_sms': event.sms,
          'p_email': event.email,
          'p_push': event.push,
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke lagre valget')),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _setChannel(String channel, bool enabled) async {
    final previous = [
      for (final event in _events) (event.sms, event.email, event.push),
    ];
    setState(() {
      _savingId = '*';
      for (final event in _events) {
        if (channel == 'sms') event.sms = enabled;
        if (channel == 'email') event.email = enabled;
        if (channel == 'push') event.push = enabled;
      }
    });
    try {
      await Supabase.instance.client.rpc(
        'set_my_notification_channel',
        params: {'p_channel': channel, 'p_enabled': enabled},
      );
    } catch (_) {
      try {
        for (final event in _events) {
          await Supabase.instance.client.rpc(
            'set_my_notification_preference',
            params: {
              'p_event_id': event.id,
              'p_sms': event.sms,
              'p_email': event.email,
              'p_push': event.push,
            },
          );
        }
      } catch (_) {
        if (!mounted) return;
        for (var i = 0; i < _events.length && i < previous.length; i++) {
          _events[i].sms = previous[i].$1;
          _events[i].email = previous[i].$2;
          _events[i].push = previous[i].$3;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke oppdatere varslene')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _events.where((e) {
      if (query.isEmpty) return true;
      return e.title.toLowerCase().contains(query) ||
          e.subtitle.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mine varsler')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      'Du ser bare varsler for sider og funksjoner du har tilgang til. '
                      'Bryterne øverst gjelder alle samtidig.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MasterChannels(
                      sms: _events.isNotEmpty && _events.every((e) => e.sms),
                      email: _events.isNotEmpty && _events.every((e) => e.email),
                      push: _events.isNotEmpty && _events.every((e) => e.push),
                      enabled: _savingId == null && _events.isNotEmpty,
                      onSms: (v) => _setChannel('sms', v),
                      onEmail: (v) => _setChannel('email', v),
                      onPush: (v) => _setChannel('push', v),
                    ),
                    if (_events.length > 4) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Søk i varsler',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Text('Ingen varsler å vise.'),
                      ),
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i == 0 || visible[i].category != visible[i - 1].category)
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 6),
                          child: Text(
                            visible[i].category,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: DriftProTheme.primaryGreen,
                            ),
                          ),
                        ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                visible[i].title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (visible[i].subtitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    visible[i].subtitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              NotificationTriChannelPicker(
                                smsEnabled: visible[i].sms,
                                emailEnabled: visible[i].email,
                                pushEnabled: visible[i].push,
                                enabled: _savingId == null,
                                onSmsChanged: (v) {
                                  setState(() => visible[i].sms = v);
                                  _save(visible[i]);
                                },
                                onEmailChanged: (v) {
                                  setState(() => visible[i].email = v);
                                  _save(visible[i]);
                                },
                                onPushChanged: (v) {
                                  setState(() => visible[i].push = v);
                                  _save(visible[i]);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _MasterChannels extends StatelessWidget {
  const _MasterChannels({
    required this.sms,
    required this.email,
    required this.push,
    required this.enabled,
    required this.onSms,
    required this.onEmail,
    required this.onPush,
  });

  final bool sms;
  final bool email;
  final bool push;
  final bool enabled;
  final ValueChanged<bool> onSms;
  final ValueChanged<bool> onEmail;
  final ValueChanged<bool> onPush;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Alle varsler',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Slå av eller på en kanal for alt du har tilgang til.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            NotificationTriChannelPicker(
              smsEnabled: sms,
              emailEnabled: email,
              pushEnabled: push,
              enabled: enabled,
              onSmsChanged: onSms,
              onEmailChanged: onEmail,
              onPushChanged: onPush,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Prøv igjen')),
          ],
        ),
      ),
    );
  }
}
