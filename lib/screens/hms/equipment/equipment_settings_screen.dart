import 'package:flutter/material.dart';

import '../../../core/services/hms/equipment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Varselinnstillinger — superadmin / admin / avdelingsleder med utstyr-admin.
class EquipmentSettingsScreen extends StatefulWidget {
  final UserProfile profile;

  const EquipmentSettingsScreen({super.key, required this.profile});

  @override
  State<EquipmentSettingsScreen> createState() =>
      _EquipmentSettingsScreenState();
}

class _EquipmentSettingsScreenState extends State<EquipmentSettingsScreen> {
  EquipmentNotificationSettings? _settings;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cid = widget.profile.companyId;
    if (cid == null) return;
    final s = await EquipmentService.getNotificationSettings(cid);
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await EquipmentService.saveNotificationSettings(
        _settings!,
        widget.profile.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Innstillinger lagret')),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const Scaffold(
        body: const DriftProLoadingCenter(),
      );
    }
    final s = _settings!;

    return Scaffold(
      appBar: AppBar(title: const Text('Utstyr – varsler')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Hvem skal varsles når service, vann eller inspeksjon nærmer seg?',
            style: DriftProTheme.bodySm,
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Ansvarlig ansatt'),
            subtitle: const Text('Person satt som ansvarlig på utstyret'),
            value: s.notifyResponsible,
            onChanged: (v) =>
                setState(() => _settings = EquipmentNotificationSettings(
                      companyId: s.companyId,
                      notifyResponsible: v,
                      notifyDepartmentLeader: s.notifyDepartmentLeader,
                      notifySuperadmin: s.notifySuperadmin,
                      defaultNotifyDaysBefore: s.defaultNotifyDaysBefore,
                      truckWaterIntervalDays: s.truckWaterIntervalDays,
                      truckServiceIntervalDays: s.truckServiceIntervalDays,
                    )),
          ),
          SwitchListTile(
            title: const Text('Avdelingsleder'),
            value: s.notifyDepartmentLeader,
            onChanged: (v) => setState(() {
              _settings = EquipmentNotificationSettings(
                companyId: s.companyId,
                notifyResponsible: s.notifyResponsible,
                notifyDepartmentLeader: v,
                notifySuperadmin: s.notifySuperadmin,
                defaultNotifyDaysBefore: s.defaultNotifyDaysBefore,
                truckWaterIntervalDays: s.truckWaterIntervalDays,
                truckServiceIntervalDays: s.truckServiceIntervalDays,
              );
            }),
          ),
          SwitchListTile(
            title: const Text('Superadmin / admin'),
            value: s.notifySuperadmin,
            onChanged: (v) => setState(() {
              _settings = EquipmentNotificationSettings(
                companyId: s.companyId,
                notifyResponsible: s.notifyResponsible,
                notifyDepartmentLeader: s.notifyDepartmentLeader,
                notifySuperadmin: v,
                defaultNotifyDaysBefore: s.defaultNotifyDaysBefore,
                truckWaterIntervalDays: s.truckWaterIntervalDays,
                truckServiceIntervalDays: s.truckServiceIntervalDays,
              );
            }),
          ),
          const Divider(height: 32),
          Text('Truck-intervaller', style: DriftProTheme.headingSm),
          const SizedBox(height: 12),
          _slider(
            'Varsle dager før frist',
            s.defaultNotifyDaysBefore,
            1,
            30,
            (v) => _settings = EquipmentNotificationSettings(
              companyId: s.companyId,
              notifyResponsible: s.notifyResponsible,
              notifyDepartmentLeader: s.notifyDepartmentLeader,
              notifySuperadmin: s.notifySuperadmin,
              defaultNotifyDaysBefore: v.round(),
              truckWaterIntervalDays: s.truckWaterIntervalDays,
              truckServiceIntervalDays: s.truckServiceIntervalDays,
            ),
          ),
          _slider(
            'Vann / batteri hver (dager)',
            s.truckWaterIntervalDays,
            1,
            30,
            (v) => _settings = EquipmentNotificationSettings(
              companyId: s.companyId,
              notifyResponsible: s.notifyResponsible,
              notifyDepartmentLeader: s.notifyDepartmentLeader,
              notifySuperadmin: s.notifySuperadmin,
              defaultNotifyDaysBefore: s.defaultNotifyDaysBefore,
              truckWaterIntervalDays: v.round(),
              truckServiceIntervalDays: s.truckServiceIntervalDays,
            ),
          ),
          _slider(
            'Service hver (dager)',
            s.truckServiceIntervalDays,
            30,
            365,
            (v) => _settings = EquipmentNotificationSettings(
              companyId: s.companyId,
              notifyResponsible: s.notifyResponsible,
              notifyDepartmentLeader: s.notifyDepartmentLeader,
              notifySuperadmin: s.notifySuperadmin,
              defaultNotifyDaysBefore: s.defaultNotifyDaysBefore,
              truckWaterIntervalDays: s.truckWaterIntervalDays,
              truckServiceIntervalDays: v.round(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Gi ansatte tilgang til servicehefter under Ansatte → tilganger: '
            '«Utstyr – servicehefter» og «Utstyr – registrere service».',
            style: DriftProTheme.caption,
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
          child: _saving
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('LAGRE INNSTILLINGER'),
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    int value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value'),
        Slider(
          value: value.toDouble(),
          min: min,
          max: max,
          divisions: (max - min).round(),
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ],
    );
  }
}
