using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Heavy. Shotgun for close-quarters defense plus an EMP grenade that area-
/// denies a wide swath of airspace for several seconds. Tougher and slower
/// than the other classes (tuned via GameRules).
/// </summary>
[Title( "Heavy Soldier" )]
[Category( "Drone vs Players/Player" )]
[Icon( "shield" )]
public sealed class HeavySoldier : SoldierBase
{
	public override SoldierClass Class => SoldierClass.Heavy;
}
