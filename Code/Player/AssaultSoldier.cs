using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Standard rifleman. Assault rifle for soldier-vs-soldier combat, chaff
/// grenade for quickly knocking a drone off them in close quarters.
/// </summary>
[Title( "Assault Soldier" )]
[Category( "Drone vs Players/Player" )]
[Icon( "military_tech" )]
public sealed class AssaultSoldier : SoldierBase
{
	public override SoldierClass Class => SoldierClass.Assault;
}
