/// Norwegian labels and constants used throughout the app.
class AppStrings {
  // ── App ──
  static const String appName = 'DriftPro';
  static const String appTagline = 'HMS & Drift – i din lomme';

  // ── Navigation ──
  static const String navDashboard = 'Dashbord';
  static const String navAbsence = 'Fravær';
  static const String navTickets = 'Avvik';
  static const String navHMS = 'HMS';
  static const String navMore = 'Mer';

  // ── Dashboard ──
  static const String greetingMorning = 'God morgen';
  static const String greetingAfternoon = 'God ettermiddag';
  static const String greetingEvening = 'God kveld';
  static const String todayAbsences = 'Dagens fravær';
  static const String openTickets = 'Åpne avvik';
  static const String criticalTickets = 'Kritiske avvik';
  static const String highRiskFindings = 'Høyrisiko-funn';
  static const String pendingSJA = 'Ventende SJA';
  static const String expiringDocuments = 'Dokumenter som utløper';
  static const String nextSafetyRound = 'Neste sikkerhetsrunde';
  static const String totalEmployees = 'Totalt ansatte';
  static const String absenceRate = 'Fraværsprosent';
  static const String quickActions = 'Hurtighandlinger';
  static const String recentActivity = 'Siste aktivitet';
  static const String overview = 'Oversikt';

  // ── Absence ──
  static const String registerAbsence = 'Registrer fravær';
  static const String selfCertification = 'Egenmelding';
  static const String sickChild = 'Sykt barn';
  static const String vacation = 'Ferie';
  static const String leave = 'Permisjon';
  static const String sickNote = 'Sykmelding';
  static const String startDate = 'Fra dato';
  static const String endDate = 'Til dato';
  static const String comment = 'Kommentar';
  static const String pending = 'Ventende';
  static const String approved = 'Godkjent';
  static const String rejected = 'Avvist';
  static const String approve = 'Godkjenn';
  static const String reject = 'Avvis';
  static const String myAbsences = 'Mine fravær';
  static const String departmentAbsences = 'Avdelingens fravær';
  static const String calendar = 'Kalender';
  static const String quotaUsage = 'Kvotebruk';
  static const String daysUsed = 'dager brukt';
  static const String daysRemaining = 'dager gjenstår';
  static const String of_ = 'av';

  // ── Tickets ──
  static const String reportDeviation = 'Meld avvik';
  static const String newTicket = 'Nytt avvik';
  static const String ticketTitle = 'Tittel';
  static const String ticketDescription = 'Beskrivelse';
  static const String ticketCategory = 'Kategori';
  static const String severity = 'Alvorlighetsgrad';
  static const String severityLow = 'Lav';
  static const String severityMedium = 'Middels';
  static const String severityHigh = 'Høy';
  static const String severityCritical = 'Kritisk';
  static const String statusOpen = 'Åpen';
  static const String statusInProgress = 'Under behandling';
  static const String statusActionTaken = 'Tiltak utført';
  static const String statusClosed = 'Lukket';
  static const String addImage = 'Legg til bilde';
  static const String addLocation = 'Legg til posisjon';
  static const String anonymous = 'Anonym melding';
  static const String assignTo = 'Tildel til';
  static const String history = 'Historikk';

  // ── Risk Assessment ──
  static const String riskAssessment = 'Risikoanalyse';
  static const String newRiskAssessment = 'Ny risikoanalyse';
  static const String probability = 'Sannsynlighet';
  static const String consequence = 'Konsekvens';
  static const String riskScore = 'Risikoscore';
  static const String existingMeasures = 'Eksisterende tiltak';
  static const String proposedMeasures = 'Foreslåtte tiltak';
  static const String riskMatrix = 'Risikomatrise';

  // ── SJA ──
  static const String sjaTitle = 'Sikker Jobb Analyse';
  static const String newSJA = 'Ny SJA';
  static const String workDescription = 'Arbeidsbeskrivelse';
  static const String hazards = 'Farer';
  static const String measures = 'Tiltak';
  static const String ppe = 'Verneutstyr';
  static const String sign = 'Signer';
  static const String signed = 'Signert';
  static const String draft = 'Utkast';

  // ── Safety Rounds ──
  static const String safetyRound = 'Sikkerhetsrunde';
  static const String newSafetyRound = 'Ny sikkerhetsrunde';
  static const String checklist = 'Sjekkliste';
  static const String findings = 'Funn';
  static const String planned = 'Planlagt';
  static const String completed = 'Fullført';

  // ── Documents ──
  static const String documents = 'Dokumenter';
  static const String personalFolder = 'Personalmappe';
  static const String uploadDocument = 'Last opp dokument';
  static const String certificate = 'Kursbevis';
  static const String license = 'Sertifikat';
  static const String employmentContract = 'Arbeidsavtale';
  static const String hmsDocument = 'HMS-dokument';
  static const String other = 'Annet';
  static const String expiresOn = 'Utløper';
  static const String documentArchive = 'Dokumentarkiv';
  static const String folders = 'Mapper';
  static const String files = 'Filer';
  static const String permissions = 'Tilganger';
  static const String rename = 'Gi nytt navn';
  static const String newFolder = 'Ny mappe';
  static const String uploadFile = 'Last opp fil';

  // ── Department & Users ──
  static const String departments = 'Avdelinger';
  static const String employees = 'Ansatte';
  static const String profile = 'Profil';
  static const String settings = 'Innstillinger';
  static const String departmentLeader = 'Avdelingsleder';
  static const String safetyRepresentative = 'Verneombud';

  // ── General Actions ──
  static const String save = 'Lagre';
  static const String cancel = 'Avbryt';
  static const String delete = 'Slett';
  static const String edit = 'Rediger';
  static const String send = 'Send';
  static const String next = 'Neste';
  static const String previous = 'Forrige';
  static const String done = 'Ferdig';
  static const String close = 'Lukk';
  static const String search = 'Søk';
  static const String filter = 'Filter';
  static const String sortBy = 'Sorter etter';
  static const String noData = 'Ingen data å vise';
  static const String loading = 'Laster...';
  static const String error = 'Noe gikk galt';
  static const String retry = 'Prøv igjen';
  static const String confirm = 'Bekreft';

  // ── Auth ──
  static const String signIn = 'Logg inn';
  static const String signOut = 'Logg ut';
  static const String signInWithGoogle = 'Logg inn med Google';
  static const String signInWithApple = 'Logg inn med Apple';
  static const String signInWithEmail = 'Logg inn med e-post';
  static const String magicLinkSent = 'Vi har sendt deg en innloggingslenke';
  static const String enterEmail = 'Skriv inn din e-postadresse';
  static const String welcomeBack = 'Velkommen tilbake';
  static const String selectCompany = 'Velg selskap';

  // ── Notifications ──
  static const String notifications = 'Varsler';
  static const String markAsRead = 'Merk som lest';
  static const String noNotifications = 'Ingen nye varsler';
}
