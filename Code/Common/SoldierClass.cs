namespace DroneVsPlayers;

/// <summary>
/// Loadout class chosen by a Soldier at round start. Each class has a fixed
/// weapon + grenade pair. See AssaultSoldier / CounterUavSoldier / HeavySoldier.
/// </summary>
public enum SoldierClass
{
	Assault = 0,
	CounterUav = 1,
	Heavy = 2,
}
