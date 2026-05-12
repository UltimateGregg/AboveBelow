using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Pellet-spread shotgun for the Heavy class. Fires N hitscan rays in a
/// cone; each pellet calls Health.RequestDamage on whatever it hits, so the
/// damage stacks naturally on a single target at close range and falls off
/// to ~one or two pellets at long range.
/// </summary>
[Title( "Shotgun Weapon" )]
[Category( "Drone vs Players/Player" )]
[Icon( "police" )]
public sealed class ShotgunWeapon : Component
{
	[Property] public string WeaponDisplayName { get; set; } = "Shotgun";
	[Property] public float DamagePerPellet { get; set; } = 9f;
	[Property] public int PelletCount { get; set; } = 8;
	[Property, Range( 0f, 15f )] public float SpreadDegrees { get; set; } = 4.5f;
	[Property] public float MaxRange { get; set; } = 2400f;
	[Property] public float FireInterval { get; set; } = 0.7f;
	[Property] public float RecoilDegrees { get; set; } = 1.4f;

	[Property] public GameObject MuzzleSocket { get; set; }
	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public GameObject TracerPrefab { get; set; }
	[Property] public SoundEvent FireSound { get; set; }

	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 34f, 9f, -12f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 AdsOffset { get; set; } = new( 22f, 0f, -6f );
	[Property] public Angles AdsRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 30f, 90f )] public float AdsFovDegrees { get; set; } = 65f;
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 20f, 15f, 55f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );

	/// <summary>Loadout slot this weapon occupies.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	TimeSince _timeSinceFire = 10f;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool IsReady => IsSelected && CooldownRemaining <= 0f;
	public float CooldownRemaining => MathF.Max( 0f, FireInterval - _timeSinceFire );
	public float CooldownReadyFraction => FireInterval <= 0f
		? 1f
		: (1f - CooldownRemaining / FireInterval).Clamp( 0f, 1f );

	protected override void OnStart()
	{
		ResolvePrefabReferences();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();

		WeaponPose.SetVisibility( GameObject, WeaponVisual, IsSelected );
		if ( IsSelected )
		{
			if ( !IsProxy )
			{
				var pc = Components.GetInAncestors<GroundPlayerController>();
				if ( pc.IsValid() )
					pc.SetAdsTarget( Input.Down( "Attack2" ), AdsFovDegrees );
			}

			WeaponPose.UpdateViewmodel(
				this, IsProxy,
				FirstPersonOffset, FirstPersonRotationOffset,
				AdsOffset, AdsRotationOffset,
				ThirdPersonLocalPosition, ThirdPersonLocalAngles );
		}

		if ( IsProxy ) return;
		if ( !IsSelected ) return;

		if ( Input.Pressed( "Attack1" ) && _timeSinceFire >= FireInterval )
		{
			Fire();
			var pc = Components.GetInAncestors<GroundPlayerController>();
			if ( pc.IsValid() )
				pc.AddRecoil( RecoilDegrees, Random.Shared.Float( -RecoilDegrees * 0.25f, RecoilDegrees * 0.25f ) );
			_timeSinceFire = 0f;
		}
	}

	void ResolvePrefabReferences()
	{
		if ( !MuzzleSocket.IsValid() )
			MuzzleSocket = GameObject.Children.FirstOrDefault( x => x.Name == "MuzzleSocket" );

		if ( !WeaponVisual.IsValid() )
			WeaponVisual = GameObject.Children.FirstOrDefault( x => x.Name == "WeaponVisual" );
	}

	void Fire()
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var lookRot = pc.EyeAngles.ToRotation();
		var origin = MuzzleSocket.IsValid() ? MuzzleSocket.WorldPosition : pc.Eye?.WorldPosition ?? WorldPosition;
		var attackerId = pc.GameObject.Id;
		var shotRotation = Random.Shared.Float( 0f, 360f );

		PlayFireSound( origin );

		for ( int i = 0; i < PelletCount; i++ )
		{
			var dir = PelletDirection( lookRot, i, PelletCount, shotRotation );

			var tr = Scene.Trace
				.Ray( origin, origin + dir * MaxRange )
				.IgnoreGameObjectHierarchy( pc.GameObject )
				.WithoutTags( "trigger" )
				.UseHitboxes()
				.Run();

			BroadcastPelletTracer( origin, tr.EndPosition );

			if ( !tr.Hit ) continue;

			var health = FindHealth( tr.GameObject );
			if ( health.IsValid() )
			{
				health.RequestDamageNamed( DamagePerPellet, attackerId, tr.HitPosition, WeaponDisplayName );
				BroadcastImpact( tr.HitPosition, (int)ImpactEffects.SurfaceKind.Flesh );
			}
			else
			{
				BroadcastImpactFromTrace( tr.HitPosition, tr.Surface?.ResourceName ?? "" );
			}
		}
	}

	[Rpc.Broadcast]
	void BroadcastImpact( Vector3 position, int surfaceKindInt )
	{
		ImpactEffects.Spawn( position, (ImpactEffects.SurfaceKind)surfaceKindInt );
	}

	[Rpc.Broadcast]
	void BroadcastImpactFromTrace( Vector3 position, string surfaceName )
	{
		var kind = ImpactEffects.SurfaceKind.Default;
		var n = surfaceName?.ToLowerInvariant() ?? "";
		if ( n.Contains( "metal" ) || n.Contains( "steel" ) || n.Contains( "alum" ) ) kind = ImpactEffects.SurfaceKind.Metal;
		else if ( n.Contains( "wood" ) ) kind = ImpactEffects.SurfaceKind.Wood;
		else if ( n.Contains( "concrete" ) || n.Contains( "stone" ) || n.Contains( "brick" ) ) kind = ImpactEffects.SurfaceKind.Concrete;
		ImpactEffects.Spawn( position, kind );
	}

	Vector3 PelletDirection( Rotation lookRot, int pelletIndex, int pelletCount, float shotRotation )
	{
		if ( pelletCount <= 1 || SpreadDegrees <= 0f )
			return lookRot.Forward;

		var t = (pelletIndex + 0.5f) / pelletCount;
		var radius = MathF.Sqrt( t ) * SpreadDegrees;
		var angle = (shotRotation + pelletIndex * 137.50777f) * (MathF.PI / 180f);
		var yaw = MathF.Cos( angle ) * radius;
		var pitch = MathF.Sin( angle ) * radius;

		return (lookRot * Rotation.From( pitch, yaw, 0f )).Forward;
	}

	static Health FindHealth( GameObject go )
	{
		if ( go is null ) return null;
		var h = go.Components.Get<Health>();
		return h.IsValid() ? h : go.Components.GetInAncestors<Health>();
	}

	[Rpc.Broadcast]
	void PlayFireSound( Vector3 from )
	{
		if ( FireSound is not null )
			Sound.Play( FireSound, from );
	}

	[Rpc.Broadcast]
	void BroadcastPelletTracer( Vector3 from, Vector3 to )
	{
		if ( TracerPrefab.IsValid() )
		{
			var tracerGo = TracerPrefab.Clone( from, Rotation.LookAt( (to - from).Normal ) );
			var line = tracerGo.Components.Get<LineRenderer>( FindMode.EverythingInSelfAndDescendants );
			if ( line.IsValid() )
			{
				line.UseVectorPoints = true;
				line.VectorPoints = new System.Collections.Generic.List<Vector3> { from, to };
			}
		}
	}
}
