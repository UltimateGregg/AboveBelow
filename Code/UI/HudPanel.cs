using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// In-game HUD panel displaying round state, local role, and local health.
/// </summary>
[Title( "HUD Panel" )]
[Category( "Drone vs Players/UI" )]
[Icon( "dashboard" )]
public partial class HudPanel
{
	string LocalRoleLabel => LocalRole switch
	{
		PlayerRole.Pilot => "ABOVE",
		PlayerRole.Soldier => "BELOW",
		_ => "SPECTATOR",
	};

	int RoundNumber => PilotWins + SoldierWins + 1;

	bool ShowRoundHeader =>
		(Round?.State is RoundState.Countdown or RoundState.Active)
		&& (LocalRole is PlayerRole.Pilot or PlayerRole.Soldier);
}
