using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Identity component for a Soldier loadout class. Sits next to the existing
/// GroundPlayerController on each soldier prefab and tags which class this
/// soldier is. Concrete classes: AssaultSoldier, CounterUavSoldier,
/// HeavySoldier. The actual weapon + grenade live as separate components on
/// the prefab; this base just exposes the class for HUD / scoring / tuning.
/// </summary>
[Title( "Soldier Base" )]
[Category( "Drone vs Players/Player" )]
[Icon( "person" )]
public abstract class SoldierBase : Component
{
	public abstract SoldierClass Class { get; }
}
