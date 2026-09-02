import 'package:flutter/material.dart';

import 'team_equal_controls.dart';

enum TeamDataScope { mine, team }

/// Min / Mine ansatte — like store segmentknapper.
class TeamScopeSegment extends StatelessWidget {
  const TeamScopeSegment({
    super.key,
    required this.scope,
    required this.onChanged,
    this.teamLabel = 'Mine ansatte',
    this.mineLabel = 'Min',
  });

  final TeamDataScope scope;
  final ValueChanged<TeamDataScope> onChanged;
  final String teamLabel;
  final String mineLabel;

  @override
  Widget build(BuildContext context) {
    return TeamEqualSegmentBar<TeamDataScope>(
      value: scope,
      onChanged: onChanged,
      items: [
        TeamEqualSegmentItem(
          value: TeamDataScope.mine,
          label: mineLabel,
          icon: Icons.person_outline,
        ),
        TeamEqualSegmentItem(
          value: TeamDataScope.team,
          label: teamLabel,
          icon: Icons.groups_outlined,
        ),
      ],
    );
  }
}
