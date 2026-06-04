/// Navigasjon inn i «Alle ruter» (f.eks. fra oversikt eller MAVI-kort).
class OwnerPortalRoutesFocus {
  /// 0 = I dag, 1 = Kommende, 2 = Tidligere
  final int tabIndex;
  final String? vehicleId;

  const OwnerPortalRoutesFocus({
    this.tabIndex = 1,
    this.vehicleId,
  });
}
