using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Simple hitscan rifle. Mount on the soldier prefab. The drone is a
/// flying target so the gun is the soldiers' primary tool. Damage is
/// authoritative on the host via a host fire request and Health.RequestDamage.
/// Shared ammo/reload/pose flow lives in WeaponBase.
/// </summary>
[Title( "Hitscan Weapon" )]
[Category( "Drone vs Players/Player" )]
[Icon( "my_location" )]
public sealed class HitscanWeapon : WeaponBase
{
	[Property] public float Damage { get; set; } = 18f;
	[Property, Range( 0f, 20f )] public float HipSpreadDegrees { get; set; } = 0f;
	[Property, Range( 0f, 20f )] public float AdsSpreadDegrees { get; set; } = 0f;
	[Property, Range( 0f, 1f )] public float AdsDynamicSpreadScale { get; set; } = 0.45f;

	[Property] public PointLight MuzzleFlash { get; set; }
	[Property] public SoundEvent FireSoundFirstPerson { get; set; }
	[Property] public SoundEvent MagDropSound { get; set; }
	[Property] public SoundEvent MagInsertSound { get; set; }
	[Property] public SoundEvent BoltRackSound { get; set; }
	[Property] public float MuzzleFlashSeconds { get; set; } = 0.045f;

	TimeSince _timeSinceMuzzleFlash = 10f;

	// Reload step scheduling. Reset to false on reload start, flipped to true
	// as each step's elapsed time is reached during OnUpdate.
	bool _playedMagDrop, _playedMagInsert, _playedBoltRack;

	public HitscanWeapon()
	{
		// Per-weapon defaults for the shared WeaponBase properties. Assigned
		// here (not as base initializers) so sparse prefab JSON deserializes
		// onto rifle values.
		WeaponDisplayName = "Rifle";
		MaxRange = 8000f;
		FireInterval = 0.12f;
		RecoilDegrees = 0.4f;
		SpreadImpulseDegrees = 0.45f;
		MaxDynamicSpreadDegrees = 3.5f;
		SpreadRecoverySeconds = 0.45f;
		MagazineSize = 30;
		StartingReserveAmmo = 120;
		ReloadSeconds = 1.65f;
		AdsOffset = new( 24f, 0f, -5f );
		AdsFovDegrees = 55f;
		HoldType = CitizenAnimationHelper.HoldTypes.Rifle;
	}

	// Automatic: fires while the trigger is held.
	protected override bool FireInputActive => Input.Down( "Attack1" );

	protected override void ApplyFireRecoil( GroundPlayerController pc )
	{
		// Camera-only recoil kick. RecoilDegrees up + small random yaw drift.
		pc.AddRecoil( RecoilDegrees, Random.Shared.Float( -RecoilDegrees * 0.3f, RecoilDegrees * 0.3f ) );
		pc.AddShotNoise(
			RecoilDegrees * 0.18f,
			Random.Shared.Float( -RecoilDegrees * 0.12f, RecoilDegrees * 0.12f ),
			Random.Shared.Float( -RecoilDegrees * 0.35f, RecoilDegrees * 0.35f ) );
	}

	protected override void OnWeaponStart()
	{
		SetMuzzleFlashVisible( false );
	}

	protected override void OnWeaponUpdate()
	{
		UpdateReloadStepSounds();
		UpdateMuzzleFlash();
	}

	protected override void OnDeselected()
	{
		SetMuzzleFlashVisible( false );
	}

	protected override void OnReloadStartFx()
	{
		_playedMagDrop = false;
		_playedMagInsert = false;
		_playedBoltRack = false;
	}

	protected override void ResolvePrefabReferences()
	{
		base.ResolvePrefabReferences();

		if ( !MuzzleFlash.IsValid() && MuzzleSocket.IsValid() )
		{
			var flashObject = MuzzleSocket.Children.FirstOrDefault( x => x.Name == "MuzzleFlash" );
			if ( flashObject.IsValid() )
				MuzzleFlash = flashObject.Components.Get<PointLight>();
		}
	}

	/// <summary>
	/// Plays per-step reload sounds (mag drop / mag insert / bolt rack) at
	/// fractional offsets through the reload duration. Each step gates on a
	/// boolean so it plays only once per reload.
	/// </summary>
	void UpdateReloadStepSounds()
	{
		if ( !IsReloading ) return;
		var elapsed = (float)_timeSinceReloadStart;
		var dur = MathF.Max( 0.05f, ReloadSeconds );

		if ( !_playedMagDrop && elapsed >= 0f )
		{
			_playedMagDrop = true;
			if ( MagDropSound is not null )
				SoundPlayback.PlayAttached( MagDropSound, GameObject, WorldPosition );
		}
		if ( !_playedMagInsert && elapsed >= dur * 0.40f )
		{
			_playedMagInsert = true;
			if ( MagInsertSound is not null )
				SoundPlayback.PlayAttached( MagInsertSound, GameObject, WorldPosition );
		}
		if ( !_playedBoltRack && elapsed >= dur * 0.78f )
		{
			_playedBoltRack = true;
			if ( BoltRackSound is not null )
				SoundPlayback.PlayAttached( BoltRackSound, GameObject, WorldPosition );
		}
	}

	void UpdateMuzzleFlash()
	{
		if ( MuzzleFlash.IsValid() && MuzzleFlash.Enabled && _timeSinceMuzzleFlash >= MuzzleFlashSeconds )
			SetMuzzleFlashVisible( false );
	}

	void SetMuzzleFlashVisible( bool visible )
	{
		if ( MuzzleFlash.IsValid() )
			MuzzleFlash.Enabled = visible;
	}

	protected override void Fire( Vector3 requestedOrigin, Vector3 aimDirection )
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var origin = ValidateFireOrigin( pc, requestedOrigin );
		var dir = aimDirection.IsNearZeroLength
			? pc.EyeAngles.ToRotation().Forward
			: aimDirection.Normal;
		dir = ApplySpread( dir, CurrentSpreadDegrees( pc ) );

		var tr = Scene.Trace
			.Ray( origin, origin + dir * MaxRange )
			.IgnoreGameObjectHierarchy( pc.GameObject )
			.WithoutTags( "trigger" )
			.UseHitboxes()
			.Run();

		PlayFireFx( origin, tr.EndPosition );
		BroadcastBulletPath( origin, tr.EndPosition );

		if ( !tr.Hit ) return;

		// Find a Health component on whatever we hit (or any ancestor).
		var health = FindHealth( tr.GameObject );
		if ( health.IsValid() )
		{
			var attackerId = DamageAttribution.OwnerConnectionId( pc.GameObject );
			health.RequestDamageNamed( Damage, attackerId, tr.HitPosition, WeaponDisplayName );
			BroadcastImpact( tr.HitPosition, tr.Normal, (int)ImpactEffects.SurfaceKind.Flesh );
		}
		else
		{
			// Surface-aware impact (concrete / metal / wood / default)
			BroadcastImpactFromTrace( tr.HitPosition, tr.Normal, tr.Surface?.ResourceName ?? "" );
		}
	}

	static Vector3 ApplySpread( Vector3 direction, float spreadDegrees )
	{
		if ( spreadDegrees <= 0f )
			return direction.Normal;

		var lookRot = Rotation.LookAt( direction.Normal );
		var radius = MathF.Sqrt( Random.Shared.Float( 0f, 1f ) ) * spreadDegrees;
		var angle = Random.Shared.Float( 0f, MathF.PI * 2f );
		var yaw = MathF.Cos( angle ) * radius;
		var pitch = MathF.Sin( angle ) * radius;

		return (lookRot * Rotation.From( pitch, yaw, 0f )).Forward;
	}

	float CurrentSpreadDegrees( GroundPlayerController pc )
	{
		var baseSpread = pc.IsValid() && pc.IsAds ? AdsSpreadDegrees : HipSpreadDegrees;
		var dynamicScale = pc.IsValid() && pc.IsAds ? AdsDynamicSpreadScale : 1f;
		return MathF.Max( 0f, baseSpread + _dynamicSpreadDegrees * dynamicScale );
	}

	/// <summary>
	/// Play a whip-by sound at the closest point on the bullet's flight path
	/// to the local player, if it passes near them without hitting them.
	/// </summary>
	[Rpc.Broadcast]
	void BroadcastBulletPath( Vector3 from, Vector3 to )
	{
		var localPlayer = Scene.GetAllComponents<GroundPlayerController>()
			.FirstOrDefault( p => !p.IsProxy );
		if ( !localPlayer.IsValid() ) return;
		// Don't whip-by yourself.
		var shooter = Components.GetInAncestors<GroundPlayerController>();
		if ( shooter.IsValid() && shooter.GameObject == localPlayer.GameObject ) return;

		var ear = localPlayer.Eye?.WorldPosition ?? localPlayer.WorldPosition + Vector3.Up * 64f;
		var seg = to - from;
		var segLen = seg.Length;
		if ( segLen < 0.01f ) return;

		var segDir = seg / segLen;
		var t = Vector3.Dot( ear - from, segDir );
		if ( t < 0f || t > segLen ) return;     // closest point is outside the segment

		var closest = from + segDir * t;
		var dist = (ear - closest).Length;
		if ( dist > 50f ) return;                // too far away to hear

		Sound.Play( "sounds/bullet_whip.sound", closest );

		// Suppression: how close the bullet passed → 1 unit at point-blank,
		// fades to 0 at 50 units. Add to the local player's suppression.
		var suppressionAmount = MathX.Lerp( 0.45f, 0.10f, dist / 50f );
		localPlayer.AddSuppression( suppressionAmount );
	}

	[Rpc.Broadcast]
	void PlayFireFx( Vector3 from, Vector3 to )
	{
		var path = to - from;
		var shotDirection = path.IsNearZeroLength ? Vector3.Forward : path.Normal;

		// Open-air "boom" everyone hears at distance.
		if ( FireSound is not null )
			SoundPlayback.PlayAttached( FireSound, MuzzleSocket.IsValid() ? MuzzleSocket : GameObject, from );

		// Close-mic'd punchy layer just for the local shooter. UI-mode sound
		// so it bypasses distance attenuation and plays at the listener.
		if ( !IsProxy && FireSoundFirstPerson is not null )
			Sound.Play( FireSoundFirstPerson );

		_timeSinceMuzzleFlash = 0f;
		SetMuzzleFlashVisible( true );
		MuzzleFlashVisual.Spawn( from, shotDirection );

		if ( TracerPrefab.IsValid() )
		{
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
			BallisticTracerRenderer.Spawn( Scene, from, to );
		}
	}
}
