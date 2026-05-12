using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Counter-UAV specialist. Carries a directional drone jammer gun and a frag
/// grenade. The jammer is the team's strongest single-target answer to
/// drones; the frag handles soldier targets and can knock damaged drones out
/// of the sky.
/// </summary>
[Title( "Counter-UAV Soldier" )]
[Category( "Drone vs Players/Player" )]
[Icon( "wifi_off" )]
public sealed class CounterUavSoldier : SoldierBase
{
	public override SoldierClass Class => SoldierClass.CounterUav;
}
