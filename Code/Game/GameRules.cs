using Sandbox;
using System;

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
	[Property] public BalanceConfigResource BalanceConfig { get; set; }

	BalanceConfigResource _fallbackBalanceConfig;

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
	[Property, Sync] public int RoundTimeSeconds { get; set; } = 180;

	/// <summary>Players needed to start (including host). Keep at 1 so solo smoke tests exercise the full round loop.</summary>
	[Property, Sync] public int MinPlayersToStart { get; set; } = 1;

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

	protected override void OnStart()
	{
		if ( !Networking.IsActive || Networking.IsHost )
			ApplyBalanceConfig();
	}

	public BalanceConfigResource GetActiveBalanceConfig()
	{
		if ( BalanceConfig is not null )
			return BalanceConfig;

		_fallbackBalanceConfig ??= new BalanceConfigResource();
		return _fallbackBalanceConfig;
	}

	public void ApplyBalanceConfig()
	{
		if ( Networking.IsActive && !Networking.IsHost )
			return;

		var config = GetActiveBalanceConfig();
		var match = config.Match ?? new MatchBalanceSettings();
		var assault = config.Assault ?? SoldierBalanceSettings.AssaultDefaults();
		var counterUav = config.CounterUav ?? SoldierBalanceSettings.CounterUavDefaults();
		var heavy = config.Heavy ?? SoldierBalanceSettings.HeavyDefaults();
		var pilotGround = config.PilotGround ?? SoldierBalanceSettings.PilotGroundDefaults();
		var gps = config.GpsDrone ?? DroneBalanceSettings.GpsDefaults();

		PilotHealth = (int)MathF.Round( gps.MaxHealth );
		SoldierHealth = (int)MathF.Round( assault.MaxHealth );
		DroneSpeedMax = gps.MaxSpeed;
		SoldierSprintSpeed = assault.SprintSpeed;
		SoldierWalkSpeed = assault.WalkSpeed;
		RoundTimeSeconds = Math.Max( 1, match.RoundTimeSeconds );
		MinPlayersToStart = Math.Max( 1, match.MinPlayersToStart );
		DroneHitscanDamage = (int)MathF.Round( gps.HitscanDamage );
		SoldierHitscanDamage = (int)MathF.Round( assault.PrimaryWeapon?.Damage ?? 12f );
		CountdownSeconds = MathF.Max( 0f, match.CountdownSeconds );
		RoundEndScreenSeconds = MathF.Max( 0.1f, match.RoundEndScreenSeconds );
		PilotTeamSize = Math.Max( 1, match.PilotTeamSize );
		SoldierTeamSize = Math.Max( 1, match.SoldierTeamSize );

		AssaultHealth = (int)MathF.Round( assault.MaxHealth );
		CounterUavHealth = (int)MathF.Round( counterUav.MaxHealth );
		HeavyHealth = (int)MathF.Round( heavy.MaxHealth );
		HeavyWalkSpeed = heavy.WalkSpeed;
		HeavySprintSpeed = heavy.SprintSpeed;

		PilotGroundHealth = (int)MathF.Round( pilotGround.MaxHealth );
		PilotGroundWalkSpeed = pilotGround.WalkSpeed;
		PilotGroundSprintSpeed = pilotGround.SprintSpeed;

		JammerGunRange = counterUav.Jammer?.MaxRange ?? 4000f;
		JammerGunConeHalfAngle = counterUav.Jammer?.ConeHalfAngle ?? 12f;

		ChaffRadius = assault.Equipment?.Radius ?? 600f;
		ChaffJamSeconds = assault.Equipment?.JamDuration ?? 3f;

		EmpRadius = heavy.Equipment?.Radius ?? 1100f;
		EmpJamSeconds = heavy.Equipment?.JamDuration ?? 6f;

		FragRadius = counterUav.Equipment?.Radius ?? 320f;
		FragDamage = counterUav.Equipment?.Damage ?? 130f;
	}
}
