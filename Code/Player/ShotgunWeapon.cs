using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Pellet-spread shotgun for the Heavy class. Fires N hitscan rays in a
/// cone; each pellet calls Health.RequestDamage on whatever it hits, so the
/// damage stacks naturally on a single target at close range and falls off
/// to ~one or two pellets at long range.
/// Shared ammo/reload/pose flow lives in WeaponBase.
/// </summary>
[Title( "Shotgun Weapon" )]
[Category( "Drone vs Players/Player" )]
[Icon( "police" )]
public sealed class ShotgunWeapon : WeaponBase
{
	[Property] public float DamagePerPellet { get; set; } = 9f;
	[Property] public int PelletCount { get; set; } = 8;
	[Property, Range( 0f, 15f )] public float SpreadDegrees { get; set; } = 4.5f;

	/// <summary>How tightly the viewmodel tracks the view. High = rigidly attached to hands; low = laggy sway.</summary>
	[Property, Range( 18f, 240f )] public float ViewmodelSwayLerpRate { get; set; } = 120f;

	public ShotgunWeapon()
	{
		// Per-weapon defaults for the shared WeaponBase properties. Assigned
		// here (not as base initializers) so sparse prefab JSON deserializes
		// onto shotgun values.
		WeaponDisplayName = "Shotgun";
		MaxRange = 2400f;
		FireInterval = 0.7f;
		RecoilDegrees = 1.4f;
		SpreadImpulseDegrees = 2.0f;
		MaxDynamicSpreadDegrees = 5.0f;
		SpreadRecoverySeconds = 0.65f;
		MagazineSize = 6;
		StartingReserveAmmo = 24;
		ReloadSeconds = 2.4f;
		AdsOffset = new( 22f, 0f, -6f );
		AdsFovDegrees = 65f;
		HoldType = CitizenAnimationHelper.HoldTypes.Shotgun;
	}

	// Semi-auto: each shot needs a fresh trigger press.
	protected override bool FireInputActive => Input.Pressed( "Attack1" );

	protected override float SwayLerpRate => ViewmodelSwayLerpRate;

	public override float CurrentAimBloom => MathF.Max( 0f, SpreadDegrees * 0.25f + _dynamicSpreadDegrees );

	protected override void ApplyFireRecoil( GroundPlayerController pc )
	{
		pc.AddRecoil( RecoilDegrees, Random.Shared.Float( -RecoilDegrees * 0.25f, RecoilDegrees * 0.25f ) );
		pc.AddShotNoise(
			RecoilDegrees * 0.22f,
			Random.Shared.Float( -RecoilDegrees * 0.10f, RecoilDegrees * 0.10f ),
			Random.Shared.Float( -RecoilDegrees * 0.45f, RecoilDegrees * 0.45f ) );
	}

	protected override void Fire( Vector3 requestedOrigin, Vector3 aimDirection )
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var origin = ValidateFireOrigin( pc, requestedOrigin );
		var aim = aimDirection.IsNearZeroLength
			? pc.EyeAngles.ToRotation().Forward
			: aimDirection.Normal;
		var lookRot = Rotation.LookAt( aim );
		var attackerId = DamageAttribution.OwnerConnectionId( pc.GameObject );
		var shotRotation = Random.Shared.Float( 0f, 360f );
		var spreadDegrees = MathF.Max( 0f, SpreadDegrees + _dynamicSpreadDegrees );

		PlayFireFx( origin, lookRot.Forward );

		for ( int i = 0; i < PelletCount; i++ )
		{
			var dir = PelletDirection( lookRot, i, PelletCount, shotRotation, spreadDegrees );

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
				BroadcastImpact( tr.HitPosition, tr.Normal, (int)ImpactEffects.SurfaceKind.Flesh );
			}
			else
			{
				BroadcastImpactFromTrace( tr.HitPosition, tr.Normal, tr.Surface?.ResourceName ?? "" );
			}
		}
	}

	Vector3 PelletDirection( Rotation lookRot, int pelletIndex, int pelletCount, float shotRotation, float spreadDegrees )
	{
		if ( pelletCount <= 1 || spreadDegrees <= 0f )
			return lookRot.Forward;

		var t = (pelletIndex + 0.5f) / pelletCount;
		var radius = MathF.Sqrt( t ) * spreadDegrees;
		var angle = (shotRotation + pelletIndex * 137.50777f) * (MathF.PI / 180f);
		var yaw = MathF.Cos( angle ) * radius;
		var pitch = MathF.Sin( angle ) * radius;

		return (lookRot * Rotation.From( pitch, yaw, 0f )).Forward;
	}

	[Rpc.Broadcast]
	void PlayFireFx( Vector3 from, Vector3 direction )
	{
		if ( FireSound is not null )
			SoundPlayback.PlayAttached( FireSound, MuzzleSocket.IsValid() ? MuzzleSocket : GameObject, from );

		MuzzleFlashVisual.Spawn( from, direction, 1.2f );
	}

	[Rpc.Broadcast]
	void BroadcastPelletTracer( Vector3 from, Vector3 to )
	{
		if ( TracerPrefab.IsValid() )
		{
			var path = to - from;
			var shotDirection = path.IsNearZeroLength ? Vector3.Forward : path.Normal;
			var tracerGo = TracerPrefab.Clone( from, Rotation.LookAt( shotDirection ) );
			var tracer = tracerGo.Components.Get<TracerLifetime>( FindMode.EverythingInSelfAndDescendants );
			if ( tracer.IsValid() )
				tracer.Configure( from, to );

			var line = tracerGo.Components.Get<LineRenderer>( FindMode.EverythingInSelfAndDescendants );
			if ( line.IsValid() && !tracer.IsValid() )
			{
				line.UseVectorPoints = true;
				line.VectorPoints = new System.Collections.Generic.List<Vector3> { from, to };
			}
		}
		else
		{
			BallisticTracerRenderer.Spawn( Scene, from, to, 0.65f );
		}
	}
}
