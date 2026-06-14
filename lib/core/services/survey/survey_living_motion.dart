/// Animert bakgrunnstype for levende undersøkelsestema.
enum SurveyLivingMotion {
  aurora,
  orbs,
  waves,
  drift,
  nordic,
  pulse,
}

extension SurveyLivingMotionFromId on String {
  SurveyLivingMotion get livingMotionFromPresetId {
    if (contains('orbs')) return SurveyLivingMotion.orbs;
    if (contains('waves')) return SurveyLivingMotion.waves;
    if (contains('drift')) return SurveyLivingMotion.drift;
    if (contains('nordic')) return SurveyLivingMotion.nordic;
    if (contains('pulse')) return SurveyLivingMotion.pulse;
    return SurveyLivingMotion.aurora;
  }
}
