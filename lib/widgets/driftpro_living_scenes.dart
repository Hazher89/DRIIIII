/// Scener som roterer én om gangen inne i D-merket.
enum DriftProLivingScene {
  routeDelivery,
  pcFiles,
  followUp,
  sickReport,
  birthday,
  hubSync,
  packageLeg,
  avvikAlert,
}

extension DriftProLivingSceneLabel on DriftProLivingScene {
  String get caption => switch (this) {
        DriftProLivingScene.routeDelivery => 'Rute A→D',
        DriftProLivingScene.pcFiles => 'Filer ut',
        DriftProLivingScene.followUp => 'Sjekkliste',
        DriftProLivingScene.sickReport => 'Syk',
        DriftProLivingScene.birthday => 'Bursdag',
        DriftProLivingScene.hubSync => 'Synk',
        DriftProLivingScene.packageLeg => 'A→B→C',
        DriftProLivingScene.avvikAlert => 'Avvik',
      };
}
