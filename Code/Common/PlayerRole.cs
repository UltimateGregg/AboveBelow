namespace DroneVsPlayers;

/// <summary>
/// Role assignment for the asymmetric mode. Exactly one Pilot per round, the
/// rest of the lobby are Soldiers. Spectator is used pre-round and on death.
/// </summary>
public enum PlayerRole
{
	Spectator = 0,
	Pilot = 1,
	Soldier = 2,
}
