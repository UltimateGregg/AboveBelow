using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Arcade hover-style drone flight model. Built on a Rigidbody but we drive
/// it through Velocity rather than forces, so behavior is predictable and
/// independent of mass tuning. Custom velocity damping provides most of the
/// hover feel, with the prefab's Rigidbody damping kept conservative.
///
/// IMPORTANT: in the Drone prefab inspector you must:
///   - set Rigidbody.Gravity = false  (we provide our own hover)
///   - use LinearDamping 2.5 and AngularDamping 12 from SETUP.md
///
/// Control mapping (defaults):
///   - W / S            forward / back  (local frame, ignores camera pitch)
///   - A / D            strafe right / left
///   - Space / Ctrl     ascend / descend
///   - Mouse X          yaw (turn left / right)
///   - Mouse Y          camera pitch only (does NOT affect flight direction)
///   - Shift            boost
///
/// "Mavic style" feel: yaw to point, sticks to translate. Easy to fly,
/// hard to crash. If you later want acro/FPV physics, fork this file.
/// </summary>
[Title( "Drone Controller" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "flight" )]
public sealed class DroneController : Component
{
	// Tuning
	[Property, Range(100, 4000)] public float MaxSpeed { get; set; } = 900f;
	[Property, Range(0.1f, 30f)] public float Acceleration { get; set; } = 8f;   // higher = snappier
	[Property, Range(0.1f, 10f)] public float Damping { get; set; } = 3.5f;       // higher = settles faster
	[Property, Range(0.5f, 5f)]  public float BoostMultiplier { get; set; } = 1.6f;
	[Property, Range(30, 360)]   public float YawRateDegrees { get; set; } = 140f;
	[Property, Range(0f, 5f)]    public float MouseLookDeadZone { get; set; } = 0.15f;
	[Property, Range(0.01f, 1f)] public float MouseYawSensitivity { get; set; } = 0.1f;
	[Property, Range(0.01f, 1f)] public float MousePitchSensitivity { get; set; } = 0.05f;

	// How much the visual model leans into its movement (purely cosmetic)
	[Property, Range(0, 35)] public float VisualTiltDegrees { get; set; } = 18f;
	[Property, Range(1f, 20f)] public float VisualTiltSmoothing { get; set; } = 6f;
	[Property, Range(0f, 6000f)] public float PropellerSpinDegreesPerSecond { get; set; } = 2160f;
	[Property, Range(0f, 1f)] public float PropellerIdleSpinFraction { get; set; } = 0.35f;
	[Property, Range(1f, 2f)] public float PropellerBoostSpinMultiplier { get; set; } = 1.25f;
	[Property] public SoundEvent PropellerSound { get; set; }
	[Property, Range(0f, 1f)] public float PropellerSoundVolume { get; set; } = 0.35f;
	[Property, Range(0.25f, 2f)] public float PropellerIdlePitch { get; set; } = 0.85f;
	[Property, Range(0.25f, 3f)] public float PropellerMaxPitch { get; set; } = 1.35f;
	[Property] public GameObject VisualModel { get; set; }

	[Property] public Rigidbody Body { get; set; }
	readonly List<GameObject> _propellers = new();
	SoundHandle _propellerSound;

	// Networked authoritative state. Owner integrates physics; others mirror.
	[Sync] public Angles EyeAngles { get; set; }
	[Sync] public bool BoostActive { get; set; }

	/// <summary>
	/// Local control gate. Set false by JammingReceiver while the drone is
	/// being jammed, or by PilotLink once the drone enters its crash sequence.
	/// When false, input is ignored — the drone coasts on whatever velocity
	/// it had, with damping applied as normal.
	/// </summary>
	public bool InputEnabled { get; set; } = true;

	public void SetInputEnabled( bool enabled ) => InputEnabled = enabled;

	protected override void OnStart()
	{
		if ( !Body.IsValid() )
			Body = Components.Get<Rigidbody>();

		if ( Body.IsValid() )
			Body.Gravity = false;

		if ( !VisualModel.IsValid() )
			VisualModel = GameObject.Children.FirstOrDefault( x => x.Name == "Visual" );

		ResolvePropellers();

		if ( !IsProxy )
			EyeAngles = WorldRotation.Angles();
	}

	protected override void OnUpdate()
	{
		var localControlActive = RemoteController.IsLocalDroneViewActive( Scene );

		if ( !IsProxy && InputEnabled && localControlActive )
		{
			// Mouse drives yaw + camera pitch. Pitch is decoupled from movement.
			var mouse = Input.MouseDelta;
			var mouseX = MathF.Abs( mouse.x ) >= MouseLookDeadZone ? mouse.x : 0f;
			var mouseY = MathF.Abs( mouse.y ) >= MouseLookDeadZone ? mouse.y : 0f;

			var ee = EyeAngles;
			ee.yaw -= mouseX * MouseYawSensitivity;
			ee.pitch += mouseY * MousePitchSensitivity;
			ee.pitch = ee.pitch.Clamp( -75f, 35f );
			ee.roll = 0;
			EyeAngles = ee;

			BoostActive = Input.Down( "Run" );
		}
		else if ( !IsProxy )
		{
			BoostActive = false;
		}

		ApplyVisualTilt();
		SpinPropellers();
		UpdatePropellerSound();
	}

	protected override void OnDestroy()
	{
		StopPropellerSound( 0.1f );
	}

	protected override void OnFixedUpdate()
	{
		if ( IsProxy ) return;
		if ( !Body.IsValid() ) return;

		// Yaw the drone GameObject around world-up to face EyeAngles.yaw.
		// Pitch/roll stay level so the physics body doesn't fight a tilted Rigidbody.
		var targetRot = Rotation.From( 0, EyeAngles.yaw, 0 );
		WorldRotation = Rotation.Slerp( WorldRotation, targetRot, Time.Delta * 8f );

		// Build wish direction in the drone's yaw-only frame.
		// While input is gated (jammed / crashing) the drone coasts on its
		// existing velocity with damping — no thrust applied. Same goes for
		// when the local pilot has toggled out of drone view.
		var localControlActive = RemoteController.IsLocalDroneViewActive( Scene );
		var inputActive = InputEnabled && localControlActive;
		Vector3 move = inputActive ? Input.AnalogMove : Vector3.Zero;
		float vertical = 0f;
		if ( inputActive )
		{
			if ( Input.Down( "Jump" ) ) vertical += 1f;
			if ( Input.Down( "Duck" ) || Input.Down( "Crouch", false ) ) vertical -= 1f;
		}

		var wish = (targetRot.Forward * move.x) + (targetRot.Right * -move.y) + (Vector3.Up * vertical);
		if ( !wish.IsNearZeroLength ) wish = wish.Normal;

		var maxSpeed = MaxSpeed * (BoostActive ? BoostMultiplier : 1f);
		var targetVelocity = wish * maxSpeed;

		// Custom damping toward target velocity. Frame-rate independent via
		// exponential decay; tune via Acceleration / Damping properties.
		var current = Body.Velocity;
		var blend = 1f - MathF.Exp( -Acceleration * Time.Delta );
		var damped = current.LerpTo( Vector3.Zero, 1f - MathF.Exp( -Damping * Time.Delta ) );
		Body.Velocity = Vector3.Lerp( damped, targetVelocity, blend );

		// Hard speed cap as a safety net.
		if ( Body.Velocity.Length > maxSpeed )
			Body.Velocity = Body.Velocity.Normal * maxSpeed;
	}

	/// <summary>
	/// Cosmetic body tilt: lean the visual model in the direction the drone
	/// is accelerating. Doesn't affect physics.
	/// </summary>
	void ApplyVisualTilt()
	{
		if ( !VisualModel.IsValid() || !Body.IsValid() ) return;

		var localVel = Rotation.From( 0, EyeAngles.yaw, 0 ).Inverse * Body.Velocity;
		var pitch = -(localVel.x / Math.Max( MaxSpeed, 1f )) * VisualTiltDegrees;
		var roll  = -(localVel.y / Math.Max( MaxSpeed, 1f )) * VisualTiltDegrees;
		var tilt = Rotation.From( pitch, 0, roll );

		VisualModel.LocalRotation = Rotation.Slerp( VisualModel.LocalRotation, tilt, Time.Delta * VisualTiltSmoothing );
	}

	void ResolvePropellers()
	{
		_propellers.Clear();
		AddPropellersFrom( GameObject );
	}

	void AddPropellersFrom( GameObject root )
	{
		foreach ( var child in root.Children )
		{
			if ( child.Name.StartsWith( "Propeller", StringComparison.OrdinalIgnoreCase ) )
				_propellers.Add( child );

			AddPropellersFrom( child );
		}
	}

	void SpinPropellers()
	{
		if ( _propellers.Count == 0 )
			ResolvePropellers();

		if ( _propellers.Count == 0 )
			return;

		var throttle = GetPropellerThrottle();
		var spin = PropellerSpinDegreesPerSecond * throttle * Time.Delta;
		foreach ( var propeller in _propellers )
		{
			if ( propeller.IsValid() )
				propeller.LocalRotation *= Rotation.From( 0, 0, spin );
		}
	}

	float GetPropellerThrottle()
	{
		var speedFraction = Body.IsValid()
			? (Body.Velocity.Length / MathF.Max( MaxSpeed, 1f )).Clamp( 0f, 1f )
			: 0f;

		var throttle = MathF.Max( PropellerIdleSpinFraction, speedFraction );
		if ( BoostActive )
			throttle *= PropellerBoostSpinMultiplier;

		return throttle.Clamp( 0f, PropellerBoostSpinMultiplier );
	}

	void UpdatePropellerSound()
	{
		if ( PropellerSound is null )
		{
			StopPropellerSound( 0.2f );
			return;
		}

		if ( _propellerSound is null || !_propellerSound.IsValid || _propellerSound.IsStopped )
		{
			_propellerSound = Sound.Play( PropellerSound, WorldPosition, 0.2f );
			_propellerSound.Parent = GameObject;
		}

		var throttle = GetPropellerThrottle();
		var normalizedThrottle = (throttle / MathF.Max( PropellerBoostSpinMultiplier, 1f )).Clamp( 0f, 1f );

		_propellerSound.Position = WorldPosition;
		_propellerSound.Volume = PropellerSoundVolume * normalizedThrottle;
		_propellerSound.Pitch = PropellerIdlePitch + (PropellerMaxPitch - PropellerIdlePitch) * normalizedThrottle;
	}

	void StopPropellerSound( float fadeTime )
	{
		if ( _propellerSound is null || !_propellerSound.IsValid )
			return;

		_propellerSound.Stop( fadeTime );
		_propellerSound = null;
	}
}
