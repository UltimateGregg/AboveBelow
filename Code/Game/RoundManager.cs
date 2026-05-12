using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

public enum RoundState
{
	WaitingForPlayers,
	Countdown,
	Active,
	Ended,
}

/// <summary>
/// Match flow controller. Host-authoritative. Spawns are handled by GameSetup,
/// this just gates state transitions and decides win conditions.
///
/// Win conditions (default):
///   - Pilot wins if all Soldiers are dead
///   - Soldiers win if Pilot drone is destroyed
///   - Either side wins by timeout if the other side has 0 score (TODO)
/// </summary>
[Title( "Round Manager" )]
[Category( "Drone vs Players" )]
[Icon( "timer" )]
public sealed class RoundManager : Component
{
	[Property] public GameSetup Setup { get; set; }
	[Property] public GameRules Rules { get; set; }
	[Property] public GameStats Stats { get; set; }

	[Property] public float CountdownSeconds { get; set; } = 5f;
	[Property] public float RoundLengthSeconds { get; set; } = 300f;
	[Property] public int MinPlayers { get; set; } = 1;

	[Sync] public RoundState State { get; set; } = RoundState.WaitingForPlayers;
	[Sync] public float StateEndsAt { get; set; }
	[Sync] public int StateSecondsRemaining { get; set; }

	[Sync] public int PilotWins { get; set; }
	[Sync] public int SoldierWins { get; set; }
	[Sync] public int LastWinnerInt { get; set; } = -1;     // -1 = not yet determined; cast to WinningSide

	// Track Health components and whether they've been recorded as a death
	private Dictionary<Health, bool> healthWasDead = new();
	private readonly Dictionary<Health, Action<DamageInfo>> healthKillHandlers = new();

	protected override void OnStart()
	{
		// Auto-wire GameRules and GameStats if not set in inspector
		if ( !Rules.IsValid() )
		{
			Rules = Components.Get<GameRules>() ?? Scene.GetAllComponents<GameRules>().FirstOrDefault();
			if ( !Rules.IsValid() )
				Log.Warning( "[RoundManager] GameRules component not found. Game balance settings will be unavailable." );
		}

		if ( !Stats.IsValid() )
		{
			Stats = Components.Get<GameStats>() ?? Scene.GetAllComponents<GameStats>().FirstOrDefault();
			if ( !Stats.IsValid() )
				Log.Warning( "[RoundManager] GameStats component not found. Kill/death tracking disabled." );
		}

		// Cache player names at round start
		if ( Stats.IsValid() )
			Stats.CachePlayerNames();
	}

	protected override void OnDestroy()
	{
		foreach ( var health in healthKillHandlers.Keys.ToList() )
		{
			UnsubscribeFromHealth( health );
		}

		healthWasDead.Clear();
	}

	protected override void OnFixedUpdate()
	{
		if ( !Networking.IsHost ) return;

		// Track player deaths for stats
		UpdateDeathTracking();

		switch ( State )
		{
			case RoundState.WaitingForPlayers:
				if ( Connection.All.Count >= MinPlayers )
					EnterCountdown();
				break;

			case RoundState.Countdown:
				if ( Time.Now >= StateEndsAt )
					EnterActive();
				break;

			case RoundState.Active:
				CheckWinConditions();
				if ( Time.Now >= StateEndsAt )
					EndRound( WinningSide.Soldiers ); // timer expires = pilot failed
				break;

			case RoundState.Ended:
				if ( Time.Now >= StateEndsAt )
					ResetForNextRound();
				break;
		}

		UpdateStateTimer();
	}

	void UpdateDeathTracking()
	{
		if ( !Stats.IsValid() ) return;

		// Find all Health components in the scene
		var allHealth = Scene.GetAllComponents<Health>().ToList();

		foreach ( var health in allHealth )
		{
			// Track this health component
			if ( !healthWasDead.ContainsKey( health ) )
			{
				healthWasDead[health] = false;

				// Subscribe to death notifications on this component
				// Only subscribe if we're the host to avoid duplicate recording
				if ( Networking.IsHost )
				{
					Action<DamageInfo> handler = damageInfo => OnHealthComponentKilled( health, damageInfo );
					health.OnKilled += handler;
					healthKillHandlers[health] = handler;
				}
			}

			// If just died (transition from alive to dead), record it
			if ( health.IsDead && !healthWasDead[health] )
			{
				healthWasDead[health] = true;

				// Record death - find the connection that owns this pawn
				var owningConn = FindConnectionForGameObject( health.GameObject );
				if ( owningConn is not null )
				{
					Stats.RecordDeath( owningConn.Id );
				}
			}
		}

		// Clean up entries for destroyed Health components
		var deadEntries = healthWasDead.Where( kvp => !kvp.Key.IsValid() ).Select( kvp => kvp.Key ).ToList();
		foreach ( var health in deadEntries )
		{
			UnsubscribeFromHealth( health );
		}
	}

	void OnHealthComponentKilled( Health health, DamageInfo damageInfo )
	{
		if ( !Networking.IsHost || !Stats.IsValid() ) return;

		// Record kill for the attacker
		if ( damageInfo.AttackerId != default )
		{
			var killedConnection = FindConnectionForGameObject( health.GameObject )?.Id ?? default;
			Stats.RecordKill( damageInfo.AttackerId, killedConnection );
		}
	}

	void UnsubscribeFromHealth( Health health )
	{
		if ( healthKillHandlers.TryGetValue( health, out var handler ) )
		{
			if ( health.IsValid() )
				health.OnKilled -= handler;

			healthKillHandlers.Remove( health );
		}

		healthWasDead.Remove( health );
	}

	Connection FindConnectionForGameObject( GameObject go )
	{
		// Try to find the owning connection via the Network system
		// The pawn's Owning field will tell us
		if ( go.Network.Owner is not null )
			return go.Network.Owner;

		// Fallback: check all connections' owned objects (inefficient but safe)
		foreach ( var conn in Connection.All )
		{
			if ( go.Network.Owner?.Id == conn.Id )
				return conn;
		}

		return null;
	}

	void EnterCountdown()
	{
		State = RoundState.Countdown;
		StateEndsAt = Time.Now + CountdownSeconds;
		UpdateStateTimer();
	}

	void EnterActive()
	{
		State = RoundState.Active;
		StateEndsAt = Time.Now + RoundLengthSeconds;
		UpdateStateTimer();
	}

	void CheckWinConditions()
	{
		// All pilots (ground avatars) dead → Soldier team wins. Each PilotSoldier
		// is bound to a drone via PilotLink; killing the pilot also crashes the
		// drone, so this single check covers "drone team eliminated".
		var pilots = Scene.GetAllComponents<PilotSoldier>().ToList();
		if ( pilots.Count > 0 && pilots.All( p => IsDead( p.GameObject ) ) )
		{
			EndRound( WinningSide.Soldiers );
			return;
		}

		// All soldiers dead → Pilot team wins.
		var soldiers = Scene.GetAllComponents<SoldierBase>().ToList();
		if ( soldiers.Count > 0 && soldiers.All( s => IsDead( s.GameObject ) ) )
		{
			EndRound( WinningSide.Pilot );
			return;
		}

		// Fallback for legacy single-pilot setup with no PilotSoldier in scene:
		// retain the old "all DroneController dead" check so a hand-built test
		// scene still triggers a soldier win.
		if ( pilots.Count == 0 )
		{
			var drones = Scene.GetAllComponents<DroneController>().ToList();
			if ( drones.Count > 0 && drones.All( d => IsDead( d.GameObject ) ) )
			{
				EndRound( WinningSide.Soldiers );
				return;
			}
		}
	}

	static bool IsDead( GameObject go )
	{
		if ( go is null ) return true;
		var h = go.Components.Get<Health>() ?? go.Components.GetInAncestors<Health>();
		return !h.IsValid() || h.IsDead;
	}

	void EndRound( WinningSide winner )
	{
		State = RoundState.Ended;
		StateEndsAt = Time.Now + 8f;
		UpdateStateTimer();

		if ( winner == WinningSide.Pilot ) PilotWins++;
		else SoldierWins++;
		LastWinnerInt = (int)winner;

		BroadcastRoundEnd( (int)winner );
	}

	void ResetForNextRound()
	{
		// Rotate the pilot role - simplest fairness: pilot becomes soldier,
		// next connection in line becomes pilot. Replace with skill / random
		// later if you want.
		if ( Setup.IsValid() )
		{
			var allConns = Connection.All.ToList();
			if ( allConns.Count == 0 )
			{
				EnterCountdown();
				return;
			}

			var idx = allConns.FindIndex( c => c.Id == Setup.PilotConnectionId );
			var nextIdx = (idx + 1) % allConns.Count;
			var newPilotId = allConns[nextIdx].Id;

			// Respawn current soldiers (the new and old pilots are handled by PromotePilot below).
			foreach ( var conn in allConns )
			{
				if ( conn.Id == Setup.PilotConnectionId ) continue; // current pilot, will be demoted
				if ( conn.Id == newPilotId ) continue;              // about to be promoted
				Setup.SpawnPawnFor( conn, PlayerRole.Soldier );
			}

			Setup.PromotePilot( newPilotId );
		}

		EnterCountdown();
	}

	[Rpc.Broadcast]
	void BroadcastRoundEnd( int winnerInt )
	{
		var winner = (WinningSide)winnerInt;
		var label = winner == WinningSide.Pilot ? "ABOVE" : "BELOW";
		Log.Info( $"[Round] {label} wins. Above {PilotWins} · Below {SoldierWins}" );
	}

	void UpdateStateTimer()
	{
		StateSecondsRemaining = State switch
		{
			RoundState.Countdown or RoundState.Active or RoundState.Ended => (int)Math.Ceiling( Math.Max( 0f, StateEndsAt - Time.Now ) ),
			_ => 0,
		};
	}

	public enum WinningSide { Pilot = 0, Soldiers = 1 }
}
