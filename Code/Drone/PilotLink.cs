using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Binds a drone to its ground-side pilot. When the pilot dies, the drone's
/// engines cut: gravity engages, input is disabled, and an explosion plays
/// either on impact or after a max timeout.
///
/// Host owns the cascade. Clients see <see cref="IsCrashing"/> via [Sync].
/// </summary>
[Title( "Pilot Link" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "link" )]
public sealed class PilotLink : Component
{
	[Property] public DroneController Drone { get; set; }
	[Property] public DroneBase DroneBase { get; set; }
	[Property] public Rigidbody Body { get; set; }
	[Property] public GameObject ExplosionPrefab { get; set; }

	/// <summary>Connection ID of the pilot operating this drone.</summary>
	[Sync] public Guid PilotId { get; set; }

	/// <summary>True once the pilot has been killed and the drone is falling.</summary>
	public bool IsCrashing => DroneBase.IsValid() && DroneBase.IsCrashing;

	[Property] public float CrashTimeout { get; set; } = 5f;

	Health _pilotHealth;
	Action<DamageInfo> _killHandler;
	TimeSince _timeSinceCrashStarted;
	bool _crashImpactConsumed;

	protected override void OnStart()
	{
		ResolveRefs();
		HookPilotHealth();
	}

	protected override void OnUpdate()
	{
		ResolveRefs();

		if ( !Networking.IsHost )
			return;

		// Re-bind if the pilot's Health component became available later (race
		// with spawn ordering — the pilot prefab may instantiate after us).
		if ( _pilotHealth is null || !_pilotHealth.IsValid() )
			HookPilotHealth();

		if ( !IsCrashing )
			return;

		// Crashed: enable gravity so it tumbles to the ground, then resolve.
		if ( Body.IsValid() )
			Body.Gravity = true;

		// On contact OR timeout, explode + destroy.
		if ( !_crashImpactConsumed && (HasImpacted() || _timeSinceCrashStarted >= CrashTimeout) )
		{
			_crashImpactConsumed = true;
			Detonate();
		}
	}

	bool HasImpacted()
	{
		if ( !Body.IsValid() ) return false;
		// Falling slowly + close to ground or a surface tap — cheap proxy
		// without subscribing to collision events.
		return Body.Velocity.Length < 80f && _timeSinceCrashStarted > 0.5f;
	}

	void Detonate()
	{
		BroadcastExplosionFx( WorldPosition );

		var droneHealth = Components.Get<Health>() ?? Components.GetInAncestors<Health>();
		if ( droneHealth.IsValid() )
			droneHealth.RequestDamage( 9999f, GameObject.Id, WorldPosition );
	}

	[Rpc.Broadcast]
	void BroadcastExplosionFx( Vector3 center )
	{
		if ( ExplosionPrefab.IsValid() )
			ExplosionPrefab.Clone( center );
	}

	void HookPilotHealth()
	{
		if ( PilotId == default )
			return;

		// Find the pilot's pawn by network owner.
		var pilotPawn = Scene.GetAllComponents<PilotSoldier>()
			.Select( p => p.GameObject )
			.FirstOrDefault( g => g.Network.Owner?.Id == PilotId );

		if ( pilotPawn is null )
			return;

		var h = pilotPawn.Components.Get<Health>() ?? pilotPawn.Components.GetInAncestors<Health>();
		if ( !h.IsValid() || h == _pilotHealth )
			return;

		Unhook();
		_pilotHealth = h;
		_killHandler = OnPilotKilled;
		_pilotHealth.OnKilled += _killHandler;

		// If we hooked late and the pilot is already dead, trigger now.
		if ( _pilotHealth.IsDead )
			OnPilotKilled( default );
	}

	void Unhook()
	{
		if ( _pilotHealth.IsValid() && _killHandler is not null )
			_pilotHealth.OnKilled -= _killHandler;
		_pilotHealth = null;
		_killHandler = null;
	}

	void OnPilotKilled( DamageInfo _ )
	{
		if ( !Networking.IsHost ) return;
		if ( !DroneBase.IsValid() ) return;
		if ( DroneBase.IsCrashing ) return;

		DroneBase.IsCrashing = true;
		_timeSinceCrashStarted = 0f;
		_crashImpactConsumed = false;

		if ( Drone.IsValid() ) Drone.SetInputEnabled( false );
		if ( Body.IsValid() ) Body.Gravity = true;
	}

	protected override void OnDestroy()
	{
		Unhook();
	}

	void ResolveRefs()
	{
		if ( !Drone.IsValid() )
			Drone = Components.Get<DroneController>();
		if ( !DroneBase.IsValid() )
			DroneBase = Components.Get<DroneBase>();
		if ( !Body.IsValid() )
			Body = Components.Get<Rigidbody>();
	}
}
