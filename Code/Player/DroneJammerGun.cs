using Sandbox;
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
	[Property] public float MaxRange { get; set; } = 4000f;
	[Property, Range( 1f, 45f )] public float ConeHalfAngle { get; set; } = 12f;
	[Property] public float TickInterval { get; set; } = 0.1f;
	[Property] public float PulseDuration { get; set; } = 0.3f;
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;

	[Property] public GameObject MuzzleSocket { get; set; }
	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public SoundEvent LoopSound { get; set; }

	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 30f, 8f, -10f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 AdsOffset { get; set; } = new( 22f, 0f, -5f );
	[Property] public Angles AdsRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 30f, 90f )] public float AdsFovDegrees { get; set; } = 60f;
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 20f, 15f, 55f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );

	/// <summary>Loadout slot this weapon occupies.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	TimeSince _timeSincePulse = 10f;
	SoundHandle _loop;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool IsActive { get; private set; }

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
			// Jammer doesn't have a traditional sight, but ADS still pulls
			// it in for a tighter "aimed cone" feel and tightens FOV slightly.
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

		if ( IsProxy ) { IsActive = false; UpdateLoopSound( false ); return; }

		// Holstered? force-stop the loop and bail before reading input.
		if ( !IsSelected )
		{
			IsActive = false;
			UpdateLoopSound( false );
			return;
		}

		var holding = Input.Down( "Attack1" );
		IsActive = holding;
		UpdateLoopSound( holding );

		if ( !holding ) return;
		if ( _timeSincePulse < TickInterval ) return;
		_timeSincePulse = 0f;

		EmitPulse();
	}

	protected override void OnDestroy()
	{
		IsActive = false;
		UpdateLoopSound( false );
	}

	void EmitPulse()
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var origin = MuzzleSocket.IsValid() ? MuzzleSocket.WorldPosition : pc.Eye?.WorldPosition ?? WorldPosition;
		var forward = pc.EyeAngles.ToRotation().Forward;
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

	void UpdateLoopSound( bool holding )
	{
		if ( holding && LoopSound is not null && (_loop is null || !_loop.IsValid || _loop.IsStopped) )
		{
			_loop = Sound.Play( LoopSound, WorldPosition, 0.15f );
			_loop.Parent = GameObject;
			return;
		}

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
	}
}
