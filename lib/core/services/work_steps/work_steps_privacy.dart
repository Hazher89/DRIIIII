/// Personvern og formål for «Skritt på jobb».
///
/// APPLE / GOOGLE REVIEWERS — READ THIS:
/// DriftPro (MAVI) uses Apple HealthKit / Google Health Connect ONLY to read
/// step counts for MAVI employees who voluntarily opt in.
///
/// - Audience: MAVI company employees only (not partners, not the public).
/// - Purpose: workplace wellness / voluntary step summary while at the workplace.
/// - NOT tracking: we do NOT continuously track GPS, do NOT record location trails,
///   do NOT sell or share health data with third parties, do NOT use steps for ads.
/// - Location: a one-time "when in use" check may run only when the employee syncs,
///   to verify the phone is inside the employer-defined workplace radius.
/// - Control: employees can turn this off anytime; turning off stops all reads.
/// - Data stored: daily step totals at work (aggregate), consent flag — no raw GPS path.
library;

/// Samtykkeversjon — bump når teksten endres (krever nytt samtykke).
const kWorkStepsConsentVersion = 'work_steps_v1';

const kWorkStepsFeatureTitle = 'Skritt på jobb';

const kWorkStepsShortPurpose =
    'Frivillig skrittoppsummering for MAVI-ansatte — kun når du er på arbeidsstedet. '
    'Ingen sporing. Du kan slå av når som helst.';

/// Vises før systemet ber om HealthKit / Health Connect (Apple/Google-krav).
/// Kort, én hensikt — deretter native systemdialog. Ikke lang «policy»-sheet.
const kWorkStepsConsentHeadline = '«Skritt på jobb»';

/// Matcher Info.plist / Health Connect purpose (Apple HIG / Google Play).
const kWorkStepsConsentBody =
    'DriftPro vil lese skrittene dine fra Apple Helse / Health Connect '
    'for å vise en frivillig skrittoppsummering mens du er på MAVI arbeidssted. '
    'Data deles ikke med tredjeparter. Du kan slå av når som helst.';

const kWorkStepsConsentDetail =
    'Kun dags-total på jobb lagres. Ingen GPS-sporing i bakgrunnen.';

const kWorkStepsOnlyAtWorkBanner =
    'Virker kun på jobb: skritt synkes bare når du er innenfor MAVI arbeidssted.';

const kWorkStepsNotAtWorkMessage =
    'Du er ikke innenfor arbeidsområdet nå. Skritt synkes ikke utenfor jobb.';

const kWorkStepsHubPurpose =
    'Oversikt over frivillige skritt på jobb for MAVI-ansatte. '
    'Kun aggregerte tall — ingen GPS-sporing.';

/// Info.plist / Android rationale (engelsk + norsk for review).
const kIosHealthShareUsageDescription =
    'DriftPro (MAVI) leser kun skritt for ansatte som frivillig aktiverer «Skritt på jobb». '
    'Skritt lagres bare når telefonen er på MAVI arbeidssted. '
    'Ingen sporing, ingen tredjepartsdeling. Du kan slå av når som helst.';

const kIosHealthUpdateUsageDescription =
    'DriftPro skriver ikke helse-data. Denne teksten kreves av iOS; '
    'appen ber kun om lesetilgang til skritt for frivillig «Skritt på jobb».';

const kAndroidHealthConnectRationale =
    'DriftPro needs step access only for MAVI employees who opt in to Work Steps. '
    'Steps are saved only when the phone is at the MAVI workplace. '
    'No continuous tracking. No third-party sharing. Opt out anytime.';
