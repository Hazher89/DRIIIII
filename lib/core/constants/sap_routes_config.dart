/// SAP sender Backup Form → Office 365 / Resend Inbound.
abstract final class SapRoutesConfig {
  /// Primær mottaker (Office 365).
  static const mailbox = 'driftpro@mavilogistikk.no';

  /// Legacy Resend-adresse (kan forwardes til [mailbox]).
  static const inboundAddress = 'ruter@driftpro.no';

  static const expectedSubject = 'Backup Form';
  static const senderDomain = '@elkjop.no';
}
