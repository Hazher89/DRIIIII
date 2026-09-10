/// Navigasjon inn i «Alle ruter» (f.eks. fra oversikt eller MAVI-kort).
class OwnerPortalRoutesFocus {
  /// 0 = Nye ruter (aksept), 1 = Tidligere (legacy 2 også = tidligere)
  final int tabIndex;
  final String? vehicleId;

  const OwnerPortalRoutesFocus({
    this.tabIndex = 0,
    this.vehicleId,
  });
}
