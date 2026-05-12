using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Centralized game configuration replicated to all clients.
/// Defines all balance settings: health, speeds, damage, round time, etc.
/// Changes here automatically sync across network (host authority).
/// </summary>
[Title( "Game Rules" )]
[Category( "Drone vs Players" )]
[Icon( "rule" )]
public sealed class GameRules : Component
{
	/// <summary>Pilot (drone) max health points</summary>
	[Property, Sync] public int PilotHealth { get; set; } = 60;

	/// <summary>Soldier max health points</summary>
	[Property, Sync] public int SoldierHealth { get; set; } = 100;

	/// <summary>Drone maximum movement speed</summary>
	[Property, Sync] public float DroneSpeedMax { get; set; } = 900f;

	/// <summary>Soldier sprint speed</summary>
	[Property, Sync] public float SoldierSprintSpeed { get; set; } = 320f;

	/// <summary>Soldier walk speed (default)</summary>
	[Property, Sync] public float SoldierWalkSpeed { get; set; } = 110f;

	/// <summary>Match duration in seconds before pilots auto-win</summary>
	[Property, Sync] public int RoundTimeSeconds { get; set; } = 300;

	/// <summary>Players needed to start (including host)</summary>
	[Property, Sync] public int MinPlayersToStart { get; set; } = 2;

	/// <summary>Damage per hitscan shot from drone</summary>
	[Property, Sync] public int DroneHitscanDamage { get; set; } = 8;

	/// <summary>Damage per hitscan shot from soldier</summary>
	[Property, Sync] public int SoldierHitscanDamage { get; set; } = 12;

	/// <summary>Countdown before round actually starts (seconds)</summary>
	[Property, Sync] public float CountdownSeconds { get; set; } = 5f;

	/// <summary>How long to show round-end screen before next round</summary>
	[Property, Sync] public float RoundEndScreenSeconds { get; set; } = 5f;

	// ── Team sizes ─────────────────────────────────────────────────────────

	/// <summary>How many drone pilots make up the Pilot team.</summary>
	[Property, Sync] public int PilotTeamSize { get; set; } = 3;

	/// <summary>How many soldiers make up the Soldier team.</summary>
	[Property, Sync] public int SoldierTeamSize { get; set; } = 4;

	// ── Per-soldier-class tuning ───────────────────────────────────────────

	[Property, Sync] public int AssaultHealth { get; set; } = 100;
	[Property, Sync] public int CounterUavHealth { get; set; } = 100;
	[Property, Sync] public int HeavyHealth { get; set; } = 150;

	[Property, Sync] public float HeavyWalkSpeed { get; set; } = 90f;
	[Property, Sync] public float HeavySprintSpeed { get; set; } = 240f;

	// ── Pilot ground avatar ────────────────────────────────────────────────

	[Property, Sync] public int PilotGroundHealth { get; set; } = 60;
	[Property, Sync] public float PilotGroundWalkSpeed { get; set; } = 110f;
	[Property, Sync] public float PilotGroundSprintSpeed { get; set; } = 260f;

	// ── Drone-counter equipment tuning ─────────────────────────────────────

	[Property, Sync] public float JammerGunRange { get; set; } = 4000f;
	[Property, Sync] public float JammerGunConeHalfAngle { get; set; } = 12f;

	[Property, Sync] public float ChaffRadius { get; set; } = 600f;
	[Property, Sync] public float ChaffJamSeconds { get; set; } = 3f;

	[Property, Sync] public float EmpRadius { get; set; } = 1100f;
	[Property, Sync] public float EmpJamSeconds { get; set; } = 6f;

	[Property, Sync] public float FragRadius { get; set; } = 320f;
	[Property, Sync] public float FragDamage { get; set; } = 130f;

	// ── Crash behavior ─────────────────────────────────────────────────────

	/// <summary>Max seconds between pilot KIA and forced drone explosion.</summary>
	[Property, Sync] public float DroneCrashTimeout { get; set; } = 5f;
}
