/// Sider og funksjoner i partner-innloggingen.
/// Mangler nøkkel, eller verdien er ikke `false`, betyr at siden er på.
abstract final class PartnerPortalPages {
  static const oversikt = 'oversikt';
  static const ruter = 'ruter';
  static const avvik = 'avvik';
  static const dokumenter = 'dokumenter';
  static const meldinger = 'meldinger';
  static const mer = 'mer';
  static const fri = 'fri';
  static const stempling = 'stempling';
  static const oppsummering = 'oppsummering';
  static const trekk = 'trekk';
  static const utleie = 'utleie';
  static const moter = 'moter';
  static const bilkontroll = 'bilkontroll';
  static const ansatte = 'ansatte';
  static const timeliste = 'timeliste';

  static const dock = <({String key, String label, String hint})>[
    (key: oversikt, label: 'Oversikt', hint: 'Forsiden i docken'),
    (key: ruter, label: 'Ruter', hint: 'Ruter i docken'),
    (key: avvik, label: 'Avvik', hint: 'Avvik i docken'),
    (key: dokumenter, label: 'Dokumenter', hint: 'Dokumenter i docken'),
    (key: meldinger, label: 'Meldinger', hint: 'Chat i docken'),
    (key: fri, label: 'Fri', hint: 'Fri-fanen for sjåfør'),
    (key: stempling, label: 'Stempling', hint: 'Stempling for ansatte'),
    (key: mer, label: 'Mer', hint: 'Hele Mer-fanen for bedriftsansvarlig'),
  ];

  static const moreItems = <({String key, String label, String hint})>[
    (key: oppsummering, label: 'Oppsummering', hint: 'Økonomi og arkiv'),
    (key: trekk, label: 'Trekk', hint: 'Bot og trekk'),
    (key: utleie, label: 'Utleie', hint: 'Lån av kjøretøy'),
    (key: moter, label: 'Møter og revisjon', hint: 'Møter'),
    (key: bilkontroll, label: 'Bilkontroll', hint: 'Kontroller'),
    (key: ansatte, label: 'Ansatte', hint: 'Registrere ansatte'),
    (key: timeliste, label: 'Timeliste', hint: 'Timer og timerbank'),
  ];

  static bool isOn(Map<String, dynamic>? access, String key) {
    final value = access?[key];
    if (value == false) return false;
    if (value is String && value.toLowerCase() == 'false') return false;
    return true;
  }
}
