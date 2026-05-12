using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Drone offensive ability. Two options stubbed in here:
///   Attack1 (LMB): forward-firing hitscan beam (low damage, fast cadence)
///   Attack2 (RMB): kamikaze proximity detonation (high damage, kills drone)
/// Pick one or both. The kamikaze mode is great for the asymmetric loop
/// because it forces the pilot to commit and gives ground players a
/// satisfying counter-window.
/// </summary>
[Title( "Drone Weapon" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "rocket_launch" )]
public sealed class DroneWeapon : Component
{
	[Property] public DroneController Drone { get; set; }
	[Property] public GameObject MuzzleSocket { get; set; }

	[Property] public bool EnableHitscan { get; set; } = true;
	[Property] public float HitscanDamage { get; set; } = 8f;
	[Property] public float HitscanRange { get; set; } = 5000f;
	[Property] public float HitscanInterval { get; set; } = 0.18f;

	[Property] public bool EnableKamikaze { get; set; } = true;
	[Property] public float KamikazeRadius { get; set; } = 320f;
	[Property] public float KamikazeDamage { get; set; } = 200f;
	[Property] public float KamikazeFalloff { get; set; } = 0.6f; // 1=linear, 0=full damage everywhere
	[Property] public GameObject ExplosionPrefab { get; set; }

	TimeSince _timeSinceFire = 10f;

	public bool PrimaryReady => PrimaryCooldownRemaining <= 0f;
	public float PrimaryCooldownRemaining => MathF.Max( 0f, HitscanInterval - _timeSinceFire );
	public float PrimaryReadyFraction => HitscanInterval <= 0f
		? 1f
		: (1f - PrimaryCooldownRemaining / HitscanInterval).Clamp( 0f, 1f );

	protected override void OnStart()
	{
		ResolvePrefabReferences();
	}

	protected override void OnUpdate()
	{
		if ( IsProxy ) return;

		ResolvePrefabReferences();

		if ( !RemoteController.IsLocalDroneViewActive( Scene ) )
			return;

		if ( EnableHitscan && Input.Down( "Attack1" ) && _timeSinceFire >= HitscanInterval )
		{
			FireHitscan();
			_timeSinceFire = 0f;
		}

		if ( EnableKamikaze && Input.Pressed( "Attack2" ) )
		{
			Detonate();
		}
	}

	void ResolvePrefabReferences()
	{
		if ( !Drone.IsValid() )
			Drone = Components.Get<DroneController>();

		if ( !MuzzleSocket.IsValid() )
			MuzzleSocket = GameObject.Children.FirstOrDefault( x => x.Name == "MuzzleSocket" );
	}

	void FireHitscan()
	{
		if ( !Drone.IsValid() ) return;

		var origin = MuzzleSocket.IsValid() ? MuzzleSocket.WorldPosition : WorldPosition;
		var dir = Drone.EyeAngles.ToRotation().Forward;

		var tr = Scene.Trace
			.Ray( origin, origin + dir * HitscanRange )
			.IgnoreGameObjectHierarchy( GameObject )
			.WithoutTags( "trigger" )
			.UseHitboxes()
			.Run();

		PlayHitscanFx( origin, tr.EndPosition );

		if ( !tr.Hit ) return;
		var health = FindHealth( tr.GameObject );
		if ( health.IsValid() )
			health.RequestDamage( HitscanDamage, GameObject.Id, tr.HitPosition );
	}

	void Detonate()
	{
		// Damage request: broadcasts everywhere, only host actually applies.
		RequestExplosion( WorldPosition );

		// Visual broadcast (independent so all clients see the boom).
		BroadcastExplosionFx( WorldPosition );

		// Kill the drone (so the pilot can't keep flying after detonating).
		var droneHealth = Components.Get<Health>() ?? Components.GetInAncestors<Health>();
		if ( droneHealth.IsValid() )
			droneHealth.RequestDamage( 9999f, GameObject.Id, WorldPosition );
	}

	static Health FindHealth( GameObject go )
	{
		if ( go is null ) return null;
		var h = go.Components.Get<Health>();
		return h.IsValid() ? h : go.Components.GetInAncestors<Health>();
	}

	[Rpc.Broadcast]
	void RequestExplosion( Vector3 center )
	{
		if ( !Networking.IsHost ) return;

		// Iterate every Health component in the scene and check distance.
		// More allocation-friendly than a physics query for ~dozens of pawns,
		// and avoids relying on physics-overlap APIs that may shift between
		// engine versions. For dense scenes consider a spatial hash.
		foreach ( var h in Scene.GetAllComponents<Health>() )
		{
			if ( !h.IsValid() ) continue;

			var dist = (h.WorldPosition - center).Length;
			if ( dist > KamikazeRadius ) continue;

			// Quick line-of-sight check so the explosion doesn't pass through walls.
			// If the trace hits anything before reaching the target, skip.
			var tr = Scene.Trace.Ray( center, h.WorldPosition )
				.WithoutTags( "trigger" )
				.IgnoreGameObjectHierarchy( GameObject )
				.IgnoreGameObjectHierarchy( h.GameObject )
				.Run();
			if ( tr.Hit ) continue;

			var t = (dist / KamikazeRadius).Clamp( 0f, 1f );
			var dmg = KamikazeDamage * (1f - t * KamikazeFalloff);
			h.TakeDamage( new DamageInfo { Amount = dmg, AttackerId = GameObject.Id, Position = center } );
		}
	}

	[Rpc.Broadcast]
	void BroadcastExplosionFx( Vector3 center )
	{
		if ( ExplosionPrefab.IsValid() )
			ExplosionPrefab.Clone( center );
	}

	[Rpc.Broadcast]
	void PlayHitscanFx( Vector3 from, Vector3 to )
	{
		// Hook up muzzle flash / tracer particle here
	}
}
