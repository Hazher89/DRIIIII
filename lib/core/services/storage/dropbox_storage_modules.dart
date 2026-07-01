/// Moduler som kan bruke Dropbox for store filer.
enum DropboxStorageModule {
  routes('routes', 'Rute-PDF (partnere)'),
  sapInbox('sap_inbox', 'SAP e-post innboks (rute-PDF)'),
  tickets('tickets', 'Avvik — bilder og vedlegg'),
  dms('dms', 'Dokumenter (DMS)'),
  partners('partners', 'Partner — bilder og filer'),
  partnerDeductions('partner_deductions', 'Bot/Trekk — bevis (bilde/video)'),
  employees('employees', 'Ansattfiler / personalmappe'),
  hms('hms', 'HMS — avvik, SJA, utstyr og kompetanse'),
  visionUniform('vision_uniform', 'Uniform-monitor — bruddbilder'),
  whistleblowing('whistleblowing', 'Varsling (anonym)');

  const DropboxStorageModule(this.key, this.label);
  final String key;
  final String label;

  static DropboxStorageModule? fromCategory(String category) {
    switch (category) {
      case 'routes':
        return routes;
      case 'sap_inbox':
        return sapInbox;
      case 'tickets':
        return tickets;
      case 'dms':
        return dms;
      case 'partners':
        return partners;
      case 'partner_deductions':
        return partnerDeductions;
      case 'employees':
        return employees;
      case 'hms':
        return hms;
      case 'vision_uniform':
        return visionUniform;
      case 'whistleblowing':
        return whistleblowing;
      default:
        return null;
    }
  }

  static Map<String, bool> defaultsEnabled() => {
        for (final m in DropboxStorageModule.values) m.key: true,
      };

  static Map<String, bool> fromStatusJson(Map<String, dynamic>? status) {
    final raw = status?['storage_modules'];
    final base = defaultsEnabled();
    if (raw is! Map) return base;
    for (final m in DropboxStorageModule.values) {
      final v = raw[m.key];
      if (v is bool) base[m.key] = v;
    }
    return base;
  }
}
