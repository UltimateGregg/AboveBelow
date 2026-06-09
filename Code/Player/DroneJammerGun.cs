using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Directional drone jammer (a.k.a. drone gun). While the trigger is held,
/// scans a forward cone for any drone with a JammingReceiver and re-applies
/// a short-duration jam every tick. The receiver's drone-type-specific
/// JamSusceptibility decides whether the jam actually disables the drone:
/// fiber-optic FPV ignores it.
/// </summary>
[Title( "Drone Jammer Gun" )]
[Category( "Drone vs Players/Player" )]
[Icon( "wifi_tethering_off" )]
public sealed class DroneJammerGun : Component
{
	const string DefaultBeamVisualPrefabPath = "prefabs/effects/jammer_beam.prefab";

	[Property] public float MaxRange { get; set; } = 4000f;
	[Property, Range( 1f, 45f )] public float ConeHalfAngle { get; set; } = 12f;
	[Property] public float TickInterval { get; set; } = 0.1f;
	[Property] public float PulseDuration { get; set; } = 0.3f;
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;

	[Property] public GameObject MuzzleSocket { get; set; }
	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public GameObject LeftHandIkTarget { get; set; }
	[Property] public GameObject RightHandIkTarget { get; set; }
	[Property] public SoundEvent LoopSound { get; set; }
	[Property] public bool ShowBeamVisual { get; set; } = true;
	[Property] public Color BeamVisualColor { get; set; } = new( 1f, 1f, 1f, 0.36f );
	[Property, Range( 0.5f, 12f )] public float BatteryDrainSeconds { get; set; } = 4f;
	[Property, Range( 0.5f, 20f )] public float BatteryRechargeSeconds { get; set; } = 6f;
	[Property, Range( 0f, 5f )] public float BatteryRechargeDelay { get; set; } = 0.75f;

	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 30f, 8f, -5f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 AdsOffset { get; set; } = new( 22f, 0f, -2f );
	[Property] public Angles AdsRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 30f, 90f )] public float AdsFovDegrees { get; set; } = 60f;
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 20f, 15f, 55f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public CitizenAnimationHelper.HoldTypes HoldType { get; set; } = CitizenAnimationHelper.HoldTypes.Rifle;
	[Property] public CitizenAnimationHelper.Hand Handedness { get; set; } = CitizenAnimationHelper.Hand.Both;

	/// <summary>Loadout slot this weapon occupies.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	TimeSince _timeSincePulse = 10f;
	TimeSince _timeSinceBatteryUse = 999f;
	SoundHandle _loop;
	GameObject _beamObject;
	JammerConeVisual _beamVisual;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool IsActive { get; private set; }
	public float BatteryChargeFraction { get; private set; } = 1f;
	public bool BatteryDepleted => BatteryChargeFraction <= 0.001f;

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();

		if ( ApplySelectionVisualState() )
		{
			// Jammer doesn't have a traditional sight, but ADS still pulls
			// it in for a tighter "aimed cone" feel and tightens FOV slightly.
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

		if ( IsProxy ) { IsActive = false; UpdateLoopSound( false ); HideBeamVisual(); return; }

		// Holstered? force-stop the loop and bail before reading input.
		if ( !IsSelected || LocalOptionsState.ConsumesGameplayInput )
		{
			UpdateBatteryCharge( false );
			IsActive = false;
			UpdateLoopSound( false );
			HideBeamVisual();
			return;
		}

		var wantsToJam = Input.Down( "Attack1" );
		var holding = UpdateBatteryCharge( wantsToJam );
		IsActive = holding;
		UpdateLoopSound( holding );
		UpdateBeamVisual( holding );

		if ( !holding ) return;
		if ( _timeSincePulse < TickInterval ) return;
		_timeSincePulse = 0f;

		EmitPulse();
	}

	protected override void OnDestroy()
	{
		IsActive = false;
		UpdateLoopSound( false );
		if ( _beamObject.IsValid() )
			_beamObject.Destroy();
	}

	internal bool ApplySelectionVisualState()
	{
		var selected = IsSelected;
		var visible = selected && !FirstPersonViewmodel.ShouldHideWorldHeldItem( this, selected );
		WeaponPose.SetVisibility( GameObject, visible );
		WeaponPose.ApplyHandPose( this, visible, HoldType, Handedness, LeftHandIkTarget, RightHandIkTarget );
		if ( !selected )
		{
			IsActive = false;
			UpdateLoopSound( false );
		}

		return selected;
	}

	void EmitPulse()
	{
		if ( !TryGetTraceOriginAndForward( out var origin, out var forward ) )
			return;

		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var sourceId = pc.GameObject.Id;
		var cosLimit = MathF.Cos( ConeHalfAngle * (MathF.PI / 180f) );

		foreach ( var receiver in Scene.GetAllComponents<JammingReceiver>() )
		{
			if ( !receiver.IsValid() ) continue;

			var to = receiver.WorldPosition - origin;
			var dist = to.Length;
			if ( dist <= 0f || dist > MaxRange ) continue;

			var dot = Vector3.Dot( to.Normal, forward );
			if ( dot < cosLimit ) continue;

			// Cheap LOS so jam doesn't pass through walls.
			var tr = Scene.Trace.Ray( origin, receiver.WorldPosition )
				.WithoutTags( "trigger" )
				.IgnoreGameObjectHierarchy( pc.GameObject )
				.IgnoreGameObjectHierarchy( receiver.GameObject )
				.Run();
			if ( tr.Hit ) continue;

			receiver.ApplyJam( sourceId, Strength, PulseDuration );
		}
	}

	void UpdateBeamVisual( bool active )
	{
		if ( !ShowBeamVisual || !active || !TryGetTraceOriginAndForward( out var origin, out var forward ) )
		{
			HideBeamVisual();
			return;
		}

		EnsureBeamVisual();
		if ( !_beamVisual.IsValid() )
			return;

		_beamVisual.Configure( origin, forward, MaxRange, ConeHalfAngle, BeamVisualColor, true );
	}

	bool UpdateBatteryCharge( bool wantsToJam )
	{
		BatteryChargeFraction = BatteryChargeFraction.Clamp( 0f, 1f );

		if ( wantsToJam && BatteryChargeFraction > 0f )
		{
			BatteryChargeFraction = MathF.Max(
				0f,
				BatteryChargeFraction - Time.Delta / MathF.Max( 0.1f, BatteryDrainSeconds ) );
			_timeSinceBatteryUse = 0f;
			return !BatteryDepleted;
		}

		if ( !wantsToJam && _timeSinceBatteryUse >= BatteryRechargeDelay && BatteryChargeFraction < 1f )
		{
			BatteryChargeFraction = MathF.Min(
				1f,
				BatteryChargeFraction + Time.Delta / MathF.Max( 0.1f, BatteryRechargeSeconds ) );
		}

		return false;
	}

	void HideBeamVisual()
	{
		if ( _beamVisual.IsValid() )
			_beamVisual.Hide();
	}

	void EnsureBeamVisual()
	{
		if ( _beamObject.IsValid() && _beamVisual.IsValid() )
			return;

		var beamPrefab = GameObject.GetPrefab( DefaultBeamVisualPrefabPath );
		if ( beamPrefab.IsValid() )
		{
			_beamObject = beamPrefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), name: "Jammer Beam Visual" );
			if ( _beamObject.IsValid() )
			{
				_beamObject.NetworkMode = NetworkMode.Never;
				_beamVisual = _beamObject.Components.Get<JammerConeVisual>( FindMode.EverythingInSelfAndDescendants );
				if ( _beamVisual.IsValid() )
					return;

				_beamObject.Destroy();
			}
		}

		_beamObject = new GameObject( true, "Jammer Beam Visual" )
		{
			NetworkMode = NetworkMode.Never
		};
		_beamVisual = _beamObject.Components.Create<JammerConeVisual>();
	}

	bool TryGetTraceOriginAndForward( out Vector3 origin, out Vector3 forward )
	{
		origin = WorldPosition;
		forward = WorldRotation.Forward;

		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() )
			return false;

		origin = MuzzleSocket.IsValid() ? MuzzleSocket.WorldPosition : pc.Eye?.WorldPosition ?? WorldPosition;
		forward = pc.EyeAngles.ToRotation().Forward;
		return true;
	}

	void UpdateLoopSound( bool holding )
	{
		if ( holding && LoopSound is not null && (_loop is null || !_loop.IsValid || _loop.IsStopped) )
		{
			_loop = SoundPlayback.PlayAttached( LoopSound, GameObject, WorldPosition, 0.15f );
			return;
		}

		if ( holding && _loop is not null && _loop.IsValid )
			SoundPlayback.UpdateAttached( _loop, GameObject, WorldPosition );

		if ( !holding && _loop is not null && _loop.IsValid )
		{
			_loop.Stop( 0.1f );
			_loop = null;
		}
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
}
