using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Shared base for the soldiers' magazine-fed hitscan weapons (rifle, SMG,
/// shotgun). Owns ammo/reload state, dynamic spread, the host-authoritative
/// fire request, selection visuals, and the viewmodel pose. Derived classes
/// implement the actual Fire() ray logic plus their fire-input mode and
/// recoil profile.
///
/// Defaults that differ per weapon are assigned in each derived class's
/// constructor instead of property initializers here — prefab JSON is sparse,
/// so unstored properties must still deserialize onto the right per-weapon
/// values (ctors run before deserialization applies stored values).
/// </summary>
public abstract class WeaponBase : Component
{
	// ── Combat tuning (per-weapon defaults assigned in derived ctors) ──
	[Property] public string WeaponDisplayName { get; set; }
	[Property] public float MaxRange { get; set; }
	[Property] public float FireInterval { get; set; }
	[Property] public float RecoilDegrees { get; set; }
	[Property, Range( 0f, 10f )] public float SpreadImpulseDegrees { get; set; }
	[Property, Range( 0f, 12f )] public float MaxDynamicSpreadDegrees { get; set; }
	[Property, Range( 0.05f, 2f )] public float SpreadRecoverySeconds { get; set; }
	[Property] public int MagazineSize { get; set; }
	[Property] public int StartingReserveAmmo { get; set; }
	[Property] public float ReloadSeconds { get; set; }

	// ── Prefab references (resolved by child name when unassigned) ──
	[Property] public GameObject MuzzleSocket { get; set; }
	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public GameObject LeftHandIkTarget { get; set; }
	[Property] public GameObject RightHandIkTarget { get; set; }
	[Property] public GameObject TracerPrefab { get; set; }
	[Property] public SoundEvent FireSound { get; set; }
	[Property] public SoundEvent ReloadSound { get; set; }
	[Property] public SoundEvent EmptyClickSound { get; set; }

	// ── Viewmodel / pose ──
	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 34f, 9f, -12f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 AdsOffset { get; set; }
	[Property] public Angles AdsRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 30f, 90f )] public float AdsFovDegrees { get; set; }
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 20f, 15f, 55f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public CitizenAnimationHelper.HoldTypes HoldType { get; set; }
	[Property] public CitizenAnimationHelper.Hand Handedness { get; set; } = CitizenAnimationHelper.Hand.Both;

	/// <summary>Loadout slot this weapon occupies. SoldierLoadout maps Slot1 input to slot 1.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	[Sync] public int AmmoInMagazine { get; set; }
	[Sync] public int AmmoReserve { get; set; }
	[Sync] public bool IsReloading { get; set; }
	[Sync] public float ReloadFinishTime { get; set; }

	protected TimeSince _timeSinceFire = 10f;
	protected TimeSince _timeSinceReloadStart = 10f;
	protected float _dynamicSpreadDegrees;

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
	public virtual float CurrentAimBloom => _dynamicSpreadDegrees;
	public string AmmoDisplay => IsReloading
		? $"RELOAD {ReloadRemaining:0.0}s"
		: $"{AmmoInMagazine}/{AmmoReserve}";

	// ── Derived contract ──

	/// <summary>Host-side hit resolution; runs inside the validated RequestFire.</summary>
	protected abstract void Fire( Vector3 requestedOrigin, Vector3 aimDirection );

	/// <summary>Fire trigger mode: Input.Down for automatics, Input.Pressed for semi-auto.</summary>
	protected abstract bool FireInputActive { get; }

	/// <summary>Camera recoil + shot noise applied on the firing client.</summary>
	protected abstract void ApplyFireRecoil( GroundPlayerController pc );

	/// <summary>Viewmodel tracking stiffness passed to WeaponPose.UpdateViewmodel.</summary>
	protected virtual float SwayLerpRate => 18f;

	protected virtual void OnWeaponStart() { }
	protected virtual void OnWeaponUpdate() { }
	protected virtual void OnDeselected() { }
	protected virtual void OnReloadStartFx() { }

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		if ( CanMutateState() )
			ResetAmmo();
		OnWeaponStart();
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();
		CompleteReloadIfReady();
		OnWeaponUpdate();
		UpdateWeaponPose();
		UpdateDynamicSpread();

		HandleFireInput();
	}

	void HandleFireInput()
	{
		if ( IsProxy ) return;
		if ( !IsSelected ) return;
		if ( LocalOptionsState.ConsumesGameplayInput ) return;

		// Empty-mag click — local-only audio feedback on a fresh press when
		// the magazine is dry. Forces the player to release+repress to retry
		// (which then triggers the auto-reload via RequestFire path).
		if ( Input.Pressed( "Attack1" ) && AmmoInMagazine == 0 && !IsReloading && EmptyClickSound is not null )
			SoundPlayback.PlayAttached( EmptyClickSound, GameObject, WorldPosition );

		if ( FireInputActive && _timeSinceFire >= FireInterval && AmmoInMagazine > 0 )
		{
			var pc = Components.GetInAncestors<GroundPlayerController>();
			if ( pc.IsValid() )
			{
				RequestFire( GetFireOrigin( pc ), pc.EyeAngles.ToRotation().Forward );
				ApplyFireRecoil( pc );
				AddClientPredictedSpreadImpulse();
				_timeSinceFire = 0f;
			}
		}
		else if ( FireInputActive && _timeSinceFire >= FireInterval && AmmoInMagazine == 0 && !IsReloading )
		{
			// Trigger auto-reload via the same server path when fired with empty mag.
			RequestReload();
			_timeSinceFire = 0f;
		}

		if ( Input.Pressed( "Reload" ) )
			RequestReload();
	}

	protected void ResetAmmo()
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

	protected void AddSpreadImpulse()
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
		OnReloadStartFx();
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
			ThirdPersonLocalPosition, ThirdPersonLocalAngles,
			SwayLerpRate );
	}

	internal bool ApplySelectionVisualState()
	{
		var selected = IsSelected;
		var visible = selected && !FirstPersonViewmodel.ShouldHideWorldHeldItem( this, selected );
		WeaponPose.SetVisibility( GameObject, visible );
		WeaponPose.ApplyHandPose( this, visible, HoldType, Handedness, LeftHandIkTarget, RightHandIkTarget );
		if ( !selected )
			OnDeselected();

		return selected;
	}

	protected static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;

	protected virtual void ResolvePrefabReferences()
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

	protected Vector3 GetFireOrigin( GroundPlayerController pc )
	{
		return MuzzleSocket.IsValid() ? MuzzleSocket.WorldPosition : pc.Eye?.WorldPosition ?? WorldPosition;
	}

	protected Vector3 ValidateFireOrigin( GroundPlayerController pc, Vector3 requestedOrigin )
	{
		var fallback = GetFireOrigin( pc );
		var eye = pc.Eye?.WorldPosition ?? pc.WorldPosition;

		return requestedOrigin.Distance( eye ) <= 140f
			? requestedOrigin
			: fallback;
	}

	protected static Health FindHealth( GameObject go )
	{
		if ( go is null ) return null;
		var h = go.Components.Get<Health>();
		return h.IsValid() ? h : go.Components.GetInAncestors<Health>();
	}

	[Rpc.Broadcast]
	protected void BroadcastImpact( Vector3 position, Vector3 normal, int surfaceKindInt )
	{
		ImpactEffects.Spawn( position, normal, (ImpactEffects.SurfaceKind)surfaceKindInt );
	}

	[Rpc.Broadcast]
	protected void BroadcastImpactFromTrace( Vector3 position, Vector3 normal, string surfaceName )
	{
		var kind = ImpactEffects.SurfaceKind.Default;
		var n = surfaceName?.ToLowerInvariant() ?? "";
		if ( n.Contains( "metal" ) || n.Contains( "steel" ) || n.Contains( "alum" ) ) kind = ImpactEffects.SurfaceKind.Metal;
		else if ( n.Contains( "wood" ) ) kind = ImpactEffects.SurfaceKind.Wood;
		else if ( n.Contains( "concrete" ) || n.Contains( "stone" ) || n.Contains( "brick" ) ) kind = ImpactEffects.SurfaceKind.Concrete;
		ImpactEffects.Spawn( position, normal, kind );
	}

	[Rpc.Broadcast]
	void PlayReloadFx( Vector3 from )
	{
		if ( ReloadSound is not null )
			SoundPlayback.PlayAttached( ReloadSound, GameObject, from );
	}
}
