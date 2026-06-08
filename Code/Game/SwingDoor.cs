using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// A door that swings open about its local up-axis (the GameObject origin is the
/// hinge). Opens automatically when a ground player gets close and swings shut
/// when they leave. The door keeps a <see cref="ModelCollider"/> so it blocks
/// movement while closed and stays solid at any angle.
///
/// Placement: the door model's pivot must be the hinge edge (the log_cabin_door
/// asset is authored that way). Put this on a child GameObject positioned at the
/// hinge; +<see cref="OpenAngle"/> yaws the latch edge inward. If the door swings
/// the wrong way in a playtest, negate <see cref="OpenAngle"/>.
/// </summary>
[Title( "Swing Door" )]
[Category( "Drone vs Players/Environment" )]
[Icon( "door_front" )]
public sealed class SwingDoor : Component
{
	/// <summary>Open angle in degrees (yaw about the hinge). Negative swings the other way.</summary>
	[Property, Range( -160f, 160f )] public float OpenAngle { get; set; } = 95f;

	/// <summary>How fast the door swings, in degrees per second.</summary>
	[Property, Range( 30f, 720f )] public float SwingSpeed { get; set; } = 300f;

	/// <summary>A player within this many world units (auto mode) opens the door.</summary>
	[Property, Range( 32f, 400f )] public float TriggerRange { get; set; } = 110f;

	/// <summary>Open when a ground player is near; close when none are.</summary>
	[Property] public bool AutoOpenOnProximity { get; set; } = true;

	/// <summary>Start the door already open.</summary>
	[Property] public bool StartOpen { get; set; }

	Rotation _closedLocal;
	float _angle;        // current angle (deg)
	bool _wantOpen;

	protected override void OnStart()
	{
		_closedLocal = LocalRotation;
		_wantOpen = StartOpen;
		_angle = StartOpen ? OpenAngle : 0f;
		Apply();
	}

	protected override void OnUpdate()
	{
		if ( AutoOpenOnProximity )
			_wantOpen = AnyPlayerNear();

		var goal = _wantOpen ? OpenAngle : 0f;
		var step = SwingSpeed * Time.Delta;
		var diff = goal - _angle;

		if ( MathF.Abs( diff ) <= step )
			_angle = goal;
		else
			_angle += MathF.Sign( diff ) * step;

		Apply();
	}

	/// <summary>Toggle the door (for interaction-driven use; turn off AutoOpenOnProximity).</summary>
	public void Toggle() => _wantOpen = !_wantOpen;

	void Apply() => LocalRotation = Rotation.FromYaw( _angle ) * _closedLocal;

	bool AnyPlayerNear()
	{
		var here = WorldPosition;
		var rangeSq = TriggerRange * TriggerRange;

		foreach ( var pc in Scene.GetAllComponents<GroundPlayerController>() )
		{
			if ( !pc.IsValid() )
				continue;

			if ( pc.WorldPosition.DistanceSquared( here ) <= rangeSq )
				return true;
		}

		return false;
	}
}
