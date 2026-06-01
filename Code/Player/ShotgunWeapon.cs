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
	[Property, Range( 0f, 10f )] public float SpreadImpulseDegrees { get; set; } = 2.0f;
	[Property, Range( 0f, 12f )] public float MaxDynamicSpreadDegrees { get; set; } = 5.0f;
	[Property, Range( 0.05f, 2f )] public float SpreadRecoverySeconds { get; set; } = 0.65f;
	[Property] public int MagazineSize { get; set; } = 6;
	[Property] public int StartingReserveAmmo { get; set; } = 24;
	[Property] public float ReloadSeconds { get; set; } = 2.4f;

	[Property] public GameObject MuzzleSocket { get; set; }
	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public GameObject LeftHandIkTarget { get; set; }
	[Property] public GameObject RightHandIkTarget { get; set; }
	[Property] public GameObject TracerPrefab { get; set; }
	[Property] public SoundEvent FireSound { get; set; }
	[Property] public SoundEvent ReloadSound { get; set; }
	[Property] public SoundEvent EmptyClickSound { get; set; }

	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 34f, 9f, -12f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 AdsOffset { get; set; } = new( 22f, 0f, -6f );
	[Property] public Angles AdsRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 30f, 90f )] public float AdsFovDegrees { get; set; } = 65f;
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 20f, 15f, 55f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public CitizenAnimationHelper.HoldTypes HoldType { get; set; } = CitizenAnimationHelper.HoldTypes.Shotgun;
	[Property] public CitizenAnimationHelper.Hand Handedness { get; set; } = CitizenAnimationHelper.Hand.Both;

	/// <summary>Loadout slot this weapon occupies.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	[Sync] public int AmmoInMagazine { get; set; }
	[Sync] public int AmmoReserve { get; set; }
	[Sync] public bool IsReloading { get; set; }
	[Sync] public float ReloadFinishTime { get; set; }

	TimeSince _timeSinceFire = 10f;
	TimeSince _timeSinceReloadStart = 10f;
	float _dynamicSpreadDegrees;

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
	public float CurrentAimBloom => MathF.Max( 0f, SpreadDegrees * 0.25f + _dynamicSpreadDegrees );
	public string AmmoDisplay => IsReloading
		? $"RELOAD {ReloadRemaining:0.0}s"
		: $"{AmmoInMagazine}/{AmmoReserve}";

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		if ( CanMutateState() )
			ResetAmmo();
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();
		CompleteReloadIfReady();
		UpdateDynamicSpread();

		if ( ApplySelectionVisualState() )
		{
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

		if ( IsProxy ) return;
		if ( !IsSelected ) return;
		if ( LocalOptionsState.ConsumesGameplayInput ) return;

		if ( Input.Pressed( "Attack1" ) && AmmoInMagazine == 0 && !IsReloading && EmptyClickSound is not null )
			SoundPlayback.PlayAttached( EmptyClickSound, GameObject, WorldPosition );

		if ( Input.Pressed( "Attack1" ) && _timeSinceFire >= FireInterval && AmmoInMagazine > 0 )
		{
			var pc = Components.GetInAncestors<GroundPlayerController>();
			if ( pc.IsValid() )
			{
				RequestFire( GetFireOrigin( pc ), pc.EyeAngles.ToRotation().Forward );
				pc.AddRecoil( RecoilDegrees, Random.Shared.Float( -RecoilDegrees * 0.25f, RecoilDegrees * 0.25f ) );
				pc.AddShotNoise(
					RecoilDegrees * 0.22f,
					Random.Shared.Float( -RecoilDegrees * 0.10f, RecoilDegrees * 0.10f ),
					Random.Shared.Float( -RecoilDegrees * 0.45f, RecoilDegrees * 0.45f ) );
				AddClientPredictedSpreadImpulse();
			}
			_timeSinceFire = 0f;
		}
		else if ( Input.Pressed( "Attack1" ) && _timeSinceFire >= FireInterval && AmmoInMagazine == 0 && !IsReloading )
		{
			RequestReload();
			_timeSinceFire = 0f;
		}

		if ( Input.Pressed( "Reload" ) )
			RequestReload();
	}

	internal bool ApplySelectionVisualState()
	{
		var selected = IsSelected;
		var visible = selected && !FirstPersonViewmodel.ShouldHideWorldHeldItem( this, selected );
		WeaponPose.SetVisibility( GameObject, visible );
		WeaponPose.ApplyHandPose( this, visible, HoldType, Handedness, LeftHandIkTarget, RightHandIkTarget );
		return selected;
	}

	void ResolvePrefabReferences()
	{
		if ( !MuzzleSocket.IsValid() )
			MuzzleSocket = GameObject.Children.FirstOrDefault( x => x.Name == "MuzzleSocket" );

		if ( !WeaponVisual.IsValid() )
			WeaponVisual = GameObject.Children.FirstOrDefault( x => x.Name == "WeaponVisual" );

		if ( !LeftHandIkTarget.IsValid() )
			LeftHandIkTarget = GameObject.Children.FirstOrDefault( x => x.Name == "LeftHandIk" );

		if ( !RightHandIkTarget.IsValid() )
			RightHandIkTarget = GameObject.Children.FirstOrDefault( x => x.Name == "RightHandIk" );
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

	void UpdateDynamicSpread()
	{
		if ( _dynamicSpreadDegrees <= 0f )
			return;

		var recoverySeconds = MathF.Max( 0.05f, SpreadRecoverySeconds );
		var decay = 1f - MathF.Exp( -Time.Delta / recoverySeconds );
		_dynamicSpreadDegrees = MathX.Lerp( _dynamicSpreadDegrees, 0f, decay );
		if ( _dynamicSpreadDegrees < 0.01f )
			_dynamicSpreadDegrees = 0f;
	}

	void AddSpreadImpulse()
	{
		_dynamicSpreadDegrees = MathF.Min(
			MathF.Max( 0f, MaxDynamicSpreadDegrees ),
			_dynamicSpreadDegrees + MathF.Max( 0f, SpreadImpulseDegrees ) );
	}

	void AddClientPredictedSpreadImpulse()
	{
		if ( !Networking.IsActive || Networking.IsHost )
			return;

		AddSpreadImpulse();
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
	}

	[Rpc.Broadcast]
	void RequestReload()
	{
		if ( !CanMutateState() ) return;

		CompleteReloadIfReady();
		BeginReload();
	}

	[Rpc.Host]
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
		AddSpreadImpulse();
		_timeSinceFire = 0f;

		if ( AmmoInMagazine <= 0 )
			BeginReload();
	}

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;

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

	static Health FindHealth( GameObject go )
	{
		if ( go is null ) return null;
		var h = go.Components.Get<Health>();
		return h.IsValid() ? h : go.Components.GetInAncestors<Health>();
	}

	[Rpc.Broadcast]
	void PlayFireFx( Vector3 from, Vector3 direction )
	{
		if ( FireSound is not null )
			SoundPlayback.PlayAttached( FireSound, MuzzleSocket.IsValid() ? MuzzleSocket : GameObject, from );

		MuzzleFlashVisual.Spawn( from, direction, 1.2f );
	}

	[Rpc.Broadcast]
	void PlayReloadFx( Vector3 from )
	{
		if ( ReloadSound is not null )
			SoundPlayback.PlayAttached( ReloadSound, GameObject, from );
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
