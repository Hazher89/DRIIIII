import '../../routing/app_paths.dart';
import 'assistant_corpus.dart';

/// Komplett FAQ om DriftPro-appen — det ansatte typisk spør om.
/// Holdes separat fra SOP slik at fakta-svar vinner over generiske steg-guider.
class AssistantAppFaq {
  AssistantAppFaq._();

  static List<KnowledgeChunk> chunks() => const [
        KnowledgeChunk(
          id: 'faq:whistleblowing-who',
          source: KnowledgeSourceKind.help,
          title: 'Hvem kan sende anonym anmeldelse?',
          body:
              'Alle ansatte som har tilgang til «Anonym anmeldelse» (Mer → Anonym anmeldelse) '
              'kan sende en sak. Avsenderen er alltid skjult — selv Tommy, Nico og Hazher '
              'ser ikke hvem som sendte.\n\n'
              'Du velger mottaker: Tommy Larsen, Nicola Vino og/eller Hazher Abdullah '
              '(én, flere eller alle tre). Avdelingsledere får aldri disse sakene.\n\n'
              'Du kan legge ved bilder, PDF og andre filer — lagres trygt i Dropbox. '
              'Mottakerne åpner saken i samme meny og kan lese tekst og vedlegg.',
          routePath: AppPaths.moreWhistleblowing,
          tags: [
            'anonym',
            'anmeldelse',
            'varsling',
            'whistleblowing',
            'hvem',
            'sende',
            'tommy',
            'nico',
            'hazher',
            'avdelingsleder',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:whistleblowing-how',
          source: KnowledgeSourceKind.help,
          title: 'Hvordan sender jeg anonym anmeldelse?',
          body:
              '1. Gå til Mer → Anonym anmeldelse.\n'
              '2. Velg mottaker(e): Tommy, Nico og/eller Hazher.\n'
              '3. Skriv tittel og beskrivelse.\n'
              '4. Legg eventuelt til vedlegg (bilder, PDF, Word, Excel…).\n'
              '5. Trykk «Send anmeldelse anonymt».\n\n'
              'Navnet ditt lagres ikke for mottakerne. Dette er ikke det samme som '
              'vanlig avvik under Avvik-fanen.',
          routePath: AppPaths.moreWhistleblowing,
          tags: [
            'anonym',
            'anmeldelse',
            'varsling',
            'whistleblowing',
            'hvordan',
            'sende',
            'vedlegg',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:anonymous-avvik',
          source: KnowledgeSourceKind.help,
          title: 'Anonymt avvik — hvem mottar?',
          body:
              'Når du melder avvik og slår på «Anonym», går saken kun til Tommy, Nico '
              'og/eller Hazher — du velger én, flere eller alle tre. '
              'Avdelingsledere får ikke varsel og skal ikke behandle anonyme avvik.\n\n'
              'Uten anonymitet: du kan melde til egen leder eller ledelsen '
              '(Tommy / Nico / Hazher).',
          routePath: AppPaths.tickets,
          tags: [
            'anonym',
            'avvik',
            'anonymt avvik',
            'hvem',
            'mottaker',
            'tommy',
            'nico',
            'hazher',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:avvik-normal',
          source: KnowledgeSourceKind.help,
          title: 'Hvordan melder jeg vanlig avvik?',
          body:
              '1. Bunnnavigasjon → Avvik (eller Dashboard → Nytt avvik).\n'
              '2. Velg saksbehandler: din egen leder (anbefalt) eller ledelsen.\n'
              '3. Beskriv hva som skjedde, alvorlighet og legg gjerne til bilder/GPS.\n'
              '4. Send — valgt person får varsel.\n\n'
              'Vil du være anonym? Bruk bryteren «Anonym» — da går saken kun til '
              'Tommy/Nico/Hazher. For sensitiv varsling utenfor vanlig avvik: '
              'bruk Mer → Anonym anmeldelse.',
          routePath: AppPaths.tickets,
          tags: [
            'avvik',
            'melde',
            'registrere',
            'nytt avvik',
            'hvordan',
            'saksbehandler',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:leave-egenmelding',
          source: KnowledgeSourceKind.help,
          title: 'Egenmelding — regler og kvote',
          body:
              'Egenmelding: inntil 3 kalenderdager per tilfelle, maks 4 tilfeller '
              'og 12 dager totalt i en 12-måneders periode fra ansettelsesdato '
              '(nullstilles ikke 1. januar).\n\n'
              'Søk under Fravær → ny søknad → Egenmelding. Leder godkjenner. '
              'Når kvoten er brukt opp i perioden, må du bruke sykmelding eller annen type.',
          routePath: AppPaths.absence,
          tags: [
            'egenmelding',
            'fravær',
            'kvote',
            '12 dager',
            'tilfeller',
            'syk',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:leave-ferie',
          source: KnowledgeSourceKind.help,
          title: 'Ferie — søknad og saldo',
          body:
              'Ferie følger kalenderår (f.eks. 2026). Du ser saldo under Fravær. '
              'Søk ferie med datoer — leder godkjenner under Innkommende / Mine ansatte.\n\n'
              'Minimum 25 virkedager etter ferieloven (bedriften kan ha mer). '
              'Ledere ser teamets saldo, overlapping og kan godkjenne/avvise.',
          routePath: AppPaths.absence,
          tags: ['ferie', 'fravær', 'saldo', 'søke', 'godkjenne', 'kvote'],
        ),
        KnowledgeChunk(
          id: 'faq:leave-sykt-barn',
          source: KnowledgeSourceKind.help,
          title: 'Sykt barn / omsorgspenger',
          body:
              'Sykt barn telles i samme 12-månedersperiode fra ansettelsesdato. '
              'Normalt 10 dager (15 ved 2+ barn under 12). '
              'Registrer antall barn under Mer → Profil hvis det mangler.\n\n'
              'Søk under Fravær → Sykt barn.',
          routePath: AppPaths.absence,
          tags: ['sykt barn', 'omsorgspenger', 'fravær', 'barn', 'kvote'],
        ),
        KnowledgeChunk(
          id: 'faq:org-chart',
          source: KnowledgeSourceKind.help,
          title: 'Organisasjonskart og ledelse',
          body:
              'Hierarki i DriftPro: Tommy Larsen og Nicola Vino øverst (eiere), '
              'Hazher Abdullah under dem (driftsleder), deretter avdelingsledere.\n\n'
              'Se kart under Mer → Organisasjonskart. Titler i appen viser '
              '«Daglig leder & medeier», «Medeier», «Driftsleder» — ikke systemroller '
              'som admin/superadmin.',
          routePath: AppPaths.moreOrganisasjonskart,
          tags: [
            'organisasjonskart',
            'hierarki',
            'tommy',
            'nico',
            'hazher',
            'leder',
            'avdelingsleder',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:mine-ansatte',
          source: KnowledgeSourceKind.help,
          title: 'Mine ansatte (for ledere)',
          body:
              'Under Fravær → Mine ansatte ser du teamets status: borte i dag, '
              'ventende søknader, ferie snart, saldo for ferie/egenmelding/sykt barn.\n\n'
              'Trykk en ansatt for detaljer. På web får du tabelloversikt og kan '
              'redigere feriekvote (ved ferie-admin). '
              'Egenmelding/sykt barn følger 12 mnd fra ansettelsesdato — ikke kalenderår.',
          routePath: AppPaths.absence,
          tags: [
            'mine ansatte',
            'leder',
            'godkjenne',
            'saldo',
            'team',
            'oversikt',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:login',
          source: KnowledgeSourceKind.help,
          title: 'Innlogging',
          body:
              'Ansatte logger inn med ansattnummer og passord. '
              'Standardpassord for nye brukere er ofte 000000 — bytt under '
              'Mer → Min profil → Bytt passord (minst 6 tegn).\n\n'
              'Partnere bruker eget portal-brukernavn. '
              'Konto opprettes av administrator — ikke offentlig selvregistrering.',
          routePath: AppPaths.moreProfil,
          tags: ['innlogging', 'passord', 'ansattnummer', '000000', 'profil'],
        ),
        KnowledgeChunk(
          id: 'faq:navigation',
          source: KnowledgeSourceKind.help,
          title: 'Hvor finner jeg ting i appen?',
          body:
              'Bunnnavigasjon: Dashboard, Fravær, Avvik, Arbeid/HMS (rolleavhengig), Meldinger.\n'
              'Mer-menyen: profil, personalmappe, organisasjonskart, anonym anmeldelse, '
              'hjelp, partnere (for de med tilgang), varsler, undersøkelser.\n\n'
              'Hurtighandlinger finnes også på Dashboard.',
          routePath: AppPaths.dashboard,
          tags: [
            'meny',
            'navigasjon',
            'hvor',
            'finne',
            'dashboard',
            'mer',
          ],
        ),
        KnowledgeChunk(
          id: 'faq:notifications',
          source: KnowledgeSourceKind.help,
          title: 'Varsler (push, SMS, e-post)',
          body:
              'DriftPro kan sende push, SMS og e-post ved nye avvik, fraværsavgjørelser, '
              'ruter m.m. Du styrer preferanser under Mer → Varsler / profil. '
              'Ledere varsles om saker i sin avdeling; anonyme saker går bare til valgte mottakere.',
          routePath: AppPaths.moreVarsler,
          tags: ['varsler', 'sms', 'push', 'e-post', 'notifikasjon'],
        ),
        KnowledgeChunk(
          id: 'faq:hms-overview',
          source: KnowledgeSourceKind.help,
          title: 'HMS i DriftPro',
          body:
              'HMS-modulen dekker avvik, risikoanalyse (ROS), SJA, vernerunder, '
              'utstyr, kompetanse, dokumenter (DMS) og opplæring/SOP. '
              'Åpnes via HMS/Arbeid i navigasjonen (tilgangsstyrt).',
          routePath: AppPaths.hms,
          tags: ['hms', 'sja', 'vernerunde', 'risiko', 'kompetanse', 'dms'],
        ),
        KnowledgeChunk(
          id: 'faq:partners',
          source: KnowledgeSourceKind.help,
          title: 'Partnere og ruter',
          body:
              'Partnermodulen: ruteplan, PDF, publisering til sjåfør/eier, SMS, '
              'bilutleie, kjøretøy og dokumenter. Tilgang styres per rolle. '
              'Spørsmål om ruter og bilutleie kan også stilles her i chatten.',
          routePath: AppPaths.partners,
          tags: ['partner', 'rute', 'sjåfør', 'bilutleie', 'logistikk'],
        ),
        KnowledgeChunk(
          id: 'faq:chat-assistant',
          source: KnowledgeSourceKind.help,
          title: 'Hva kan DriftPro-assistenten?',
          body:
              'Jeg er DriftPro-assistenten. Spør om hva som helst i appen: '
              'fravær, ferie, egenmelding, avvik, anonym anmeldelse, HMS, partnere, '
              'innlogging, varsler, organisasjon, bilutleie, SOP/opplæring.\n\n'
              'Still spørsmålet med egne ord — f.eks. «hvem godkjenner ferie?», '
              '«hvor mange egenmeldingsdager har jeg?», «hvordan melder jeg anonymt?».',
          routePath: AppPaths.moreAssistent,
          tags: ['assistent', 'chat', 'hjelp', 'spør', 'hva kan'],
        ),
        KnowledgeChunk(
          id: 'faq:support',
          source: KnowledgeSourceKind.help,
          title: 'Får jeg ikke svar — kontakt support',
          body:
              'Finner du ikke svaret her: e-post hazher@mavilogistikk.no '
              'eller https://hazher.no/DRIFTPRO/Support/.',
          routePath: AppPaths.moreHjelp,
          tags: ['support', 'kontakt', 'hjelp', 'epost'],
        ),
      ];
}
