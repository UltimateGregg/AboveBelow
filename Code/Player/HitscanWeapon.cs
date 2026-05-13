using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Simple hitscan rifle. Mount on the soldier prefab. The drone is a
/// flying target so the gun is the soldiers' primary tool. Damage is
/// authoritative on the host via Health.RequestDamage.
/// </summary>
[Title( "Hitscan Weapon" )]
[Category( "Drone vs Players/Player" )]
[Icon( "my_location" )]
public sealed class HitscanWeapon : Component
{
	[Property] public string WeaponDisplayName { get; set; } = "Rifle";
	[Property] public float Damage { get; set; } = 18f;
	[Property] public float MaxRange { get; set; } = 8000f;
	[Property] public float FireInterval { get; set; } = 0.12f;
	[Property] public float RecoilDegrees { get; set; } = 0.4f;
	[Property, Range( 0f, 20f )] public float HipSpreadDegrees { get; set; } = 0f;
	[Property, Range( 0f, 20f )] public float AdsSpreadDegrees { get; set; } = 0f;
	[Property] public int MagazineSize { get; set; } = 30;
	[Property] public int StartingReserveAmmo { get; set; } = 120;
	[Property] public float ReloadSeconds { get; set; } = 1.65f;

	[Property] public GameObject MuzzleSocket { get; set; }
	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public GameObject TracerPrefab { get; set; }
	[Property] public PointLight MuzzleFlash { get; set; }
	[Property] public SoundEvent FireSound { get; set; }
	[Property] public SoundEvent FireSoundFirstPerson { get; set; }
	[Property] public SoundEvent ReloadSound { get; set; }
	[Property] public SoundEvent MagDropSound { get; set; }
	[Property] public SoundEvent MagInsertSound { get; set; }
	[Property] public SoundEvent BoltRackSound { get; set; }
	[Property] public SoundEvent EmptyClickSound { get; set; }
	[Property] public float MuzzleFlashSeconds { get; set; } = 0.045f;

	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 34f, 9f, -12f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 AdsOffset { get; set; } = new( 24f, 0f, -5f );
	[Property] public Angles AdsRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 30f, 90f )] public float AdsFovDegrees { get; set; } = 55f;
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 20f, 15f, 55f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );

	/// <summary>Loadout slot this weapon occupies. SoldierLoadout maps Slot1 input to slot 1.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	[Sync] public int AmmoInMagazine { get; set; }
	[Sync] public int AmmoReserve { get; set; }
	[Sync] public bool IsReloading { get; set; }
	[Sync] public float ReloadFinishTime { get; set; }

	TimeSince _timeSinceFire = 10f;
	TimeSince _timeSinceMuzzleFlash = 10f;

	// Reload step scheduling. Reset to false on BeginReload, flipped to true as
	// each step's elapsed time is reached during OnUpdate.
	TimeSince _timeSinceReloadStart = 10f;
	bool _playedMagDrop, _playedMagInsert, _playedBoltRack;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool IsReady => IsSelected && !IsReloading && AmmoInMagazine > 0 && CooldownRemaining <= 0f;
	public float CooldownRemaining => MathF.Max( 0f, FireInterval - _timeSinceFire );
	public float CooldownReadyFraction => FireInterval <= 0f
		? 1f
		: (1f - CooldownRemaining / FireInterval).Clamp( 0f, 1f );
	public float ReloadRemaining => IsReloading ? MathF.Max( 0f, ReloadFinishTime - Time.Now ) : 0f;
	public float ReloadReadyFraction => !IsReloading || ReloadSeconds <= 0f
		? 1f
		: (1f - ReloadRemaining / ReloadSeconds).Clamp( 0f, 1f );
	public float ReadyFraction => IsReloading ? ReloadReadyFraction : CooldownReadyFraction;
	public string AmmoDisplay => IsReloading
		? $"RELOAD {ReloadRemaining:0.0}s"
		: $"{AmmoInMagazine}/{AmmoReserve}";

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		if ( CanMutateState() )
			ResetAmmo();
		SetMuzzleFlashVisible( false );
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();
		CompleteReloadIfReady();
		UpdateReloadStepSounds();
		UpdateMuzzleFlash();
		UpdateWeaponPose();

		if ( IsProxy ) return;
		if ( !IsSelected ) return;
		if ( LocalOptionsState.ConsumesGameplayInput ) return;

		// Empty-mag click — local-only audio feedback on a fresh press when
		// the magazine is dry. Forces the player to release+repress to retry
		// (which then triggers the auto-reload via RequestFire path).
		if ( Input.Pressed( "Attack1" ) && AmmoInMagazine == 0 && !IsReloading && EmptyClickSound is not null )
			Sound.Play( EmptyClickSound, WorldPosition );

		if ( Input.Down( "Attack1" ) && _timeSinceFire >= FireInterval && AmmoInMagazine > 0 )
		{
			var pc = Components.GetInAncestors<GroundPlayerController>();
			if ( pc.IsValid() )
			{
				RequestFire( GetFireOrigin( pc ), pc.EyeAngles.ToRotation().Forward );
				// Camera-only recoil kick. RecoilDegrees up + small random yaw drift.
				pc.AddRecoil( RecoilDegrees, Random.Shared.Float( -RecoilDegrees * 0.3f, RecoilDegrees * 0.3f ) );
				_timeSinceFire = 0f;
			}
		}
		else if ( Input.Down( "Attack1" ) && _timeSinceFire >= FireInterval && AmmoInMagazine == 0 && !IsReloading )
		{
			// Trigger auto-reload via the same server path when held with empty mag.
			RequestReload();
			_timeSinceFire = 0f;
		}

		if ( Input.Pressed( "Reload" ) )
		{
			RequestReload();
		}
	}

	void ResetAmmo()
	{
		AmmoInMagazine = Math.Max( 1, MagazineSize );
		AmmoReserve = Math.Max( 0, StartingReserveAmmo );
		IsReloading = false;
		ReloadFinishTime = 0f;
	}

	void CompleteReloadIfReady()
	{
		if ( !CanMutateState() ) return;
		if ( !IsReloading ) return;
		if ( Time.Now < ReloadFinishTime ) return;

		var needed = Math.Max( 0, MagazineSize - AmmoInMagazine );
		var loaded = Math.Min( needed, AmmoReserve );
		AmmoInMagazine += loaded;
		AmmoReserve -= loaded;
		IsReloading = false;
		ReloadFinishTime = 0f;
	}

	void BeginReload()
	{
		if ( IsReloading ) return;
		if ( AmmoReserve <= 0 ) return;
		if ( AmmoInMagazine >= MagazineSize ) return;

		IsReloading = true;
		ReloadFinishTime = Time.Now + MathF.Max( 0.05f, ReloadSeconds );
		PlayReloadFx( WorldPosition );
		BroadcastReloadStart();
	}

	[Rpc.Broadcast]
	void BroadcastReloadStart()
	{
		_timeSinceReloadStart = 0f;
		_playedMagDrop = false;
		_playedMagInsert = false;
		_playedBoltRack = false;
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
				Sound.Play( MagDropSound, WorldPosition );
		}
		if ( !_playedMagInsert && elapsed >= dur * 0.40f )
		{
			_playedMagInsert = true;
			if ( MagInsertSound is not null )
				Sound.Play( MagInsertSound, WorldPosition );
		}
		if ( !_playedBoltRack && elapsed >= dur * 0.78f )
		{
			_playedBoltRack = true;
			if ( BoltRackSound is not null )
				Sound.Play( BoltRackSound, WorldPosition );
		}
	}

	[Rpc.Broadcast]
	void RequestReload()
	{
		if ( !CanMutateState() ) return;

		CompleteReloadIfReady();
		BeginReload();
	}

	[Rpc.Broadcast]
	void RequestFire( Vector3 requestedOrigin, Vector3 aimDirection )
	{
		if ( !CanMutateState() ) return;

		CompleteReloadIfReady();

		if ( !IsSelected ) return;
		if ( IsReloading ) return;
		if ( _timeSinceFire < FireInterval ) return;

		if ( AmmoInMagazine <= 0 )
		{
			BeginReload();
			return;
		}

		Fire( requestedOrigin, aimDirection );
		AmmoInMagazine = Math.Max( 0, AmmoInMagazine - 1 );
		_timeSinceFire = 0f;

		if ( AmmoInMagazine <= 0 )
			BeginReload();
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

	void UpdateWeaponPose()
	{
		if ( !ApplySelectionVisualState() ) return;

		// Request ADS from the controller while right-click is held (only
		// when this weapon is selected — grenade's Attack2 throw is gated
		// by its own IsSelected check).
		if ( !IsProxy )
		{
			var pc = Components.GetInAncestors<GroundPlayerController>();
			if ( pc.IsValid() )
				pc.SetAdsTarget( !LocalOptionsState.ConsumesGameplayInput && Input.Down( "Attack2" ), AdsFovDegrees );
		}

		WeaponPose.UpdateViewmodel(
			this, IsProxy,
			FirstPersonOffset, FirstPersonRotationOffset,
			AdsOffset, AdsRotationOffset,
			ThirdPersonLocalPosition, ThirdPersonLocalAngles );
	}

	internal bool ApplySelectionVisualState()
	{
		var selected = IsSelected;
		WeaponPose.SetVisibility( GameObject, selected );
		if ( !selected )
			SetMuzzleFlashVisible( false );

		return selected;
	}

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;

	void ResolvePrefabReferences()
	{
		if ( !MuzzleSocket.IsValid() )
			MuzzleSocket = GameObject.Children.FirstOrDefault( x => x.Name == "MuzzleSocket" );

		if ( !WeaponVisual.IsValid() )
			WeaponVisual = GameObject.Children.FirstOrDefault( x => x.Name == "WeaponVisual" );

		if ( !MuzzleFlash.IsValid() && MuzzleSocket.IsValid() )
		{
			var flashObject = MuzzleSocket.Children.FirstOrDefault( x => x.Name == "MuzzleFlash" );
			if ( flashObject.IsValid() )
				MuzzleFlash = flashObject.Components.Get<PointLight>();
		}
	}

	Vector3 GetFireOrigin( GroundPlayerController pc )
	{
		return MuzzleSocket.IsValid() ? MuzzleSocket.WorldPosition : pc.Eye?.WorldPosition ?? WorldPosition;
	}

	Vector3 ValidateFireOrigin( GroundPlayerController pc, Vector3 requestedOrigin )
	{
		var fallback = GetFireOrigin( pc );
		var eye = pc.Eye?.WorldPosition ?? pc.WorldPosition;

		return requestedOrigin.Distance( eye ) <= 140f
			? requestedOrigin
			: fallback;
	}

	void Fire( Vector3 requestedOrigin, Vector3 aimDirection )
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var origin = ValidateFireOrigin( pc, requestedOrigin );
		var dir = aimDirection.IsNearZeroLength
			? pc.EyeAngles.ToRotation().Forward
			: aimDirection.Normal;
		dir = ApplySpread( dir, pc.IsAds ? AdsSpreadDegrees : HipSpreadDegrees );

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
			BroadcastImpact( tr.HitPosition, (int)ImpactEffects.SurfaceKind.Flesh );
		}
		else
		{
			// Surface-aware impact (concrete / metal / wood / default)
			BroadcastImpactFromTrace( tr.HitPosition, tr.Surface?.ResourceName ?? "" );
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

	static Health FindHealth( GameObject go )
	{
		if ( go is null ) return null;
		var h = go.Components.Get<Health>();
		return h.IsValid() ? h : go.Components.GetInAncestors<Health>();
	}

	[Rpc.Broadcast]
	void PlayFireFx( Vector3 from, Vector3 to )
	{
		var path = to - from;
		var shotDirection = path.IsNearZeroLength ? Vector3.Forward : path.Normal;

		// Open-air "boom" everyone hears at distance.
		if ( FireSound is not null )
			Sound.Play( FireSound, from );

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
	}

	[Rpc.Broadcast]
	void PlayReloadFx( Vector3 from )
	{
		if ( ReloadSound is not null )
			Sound.Play( ReloadSound, from );
	}
}
