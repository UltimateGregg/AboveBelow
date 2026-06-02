using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Moves the placed startup camera upward once, then releases ownership so
/// player and drone camera controllers can drive the main camera normally.
/// </summary>
[Title( "Startup Camera Lift" )]
[Category( "Drone vs Players/Camera" )]
[Icon( "vertical_align_top" )]
public sealed class StartupCameraLift : Component
{
	[Property, Range( 0f, 5000f )] public float LiftDistanceUnits { get; set; } = 2400f;
	[Property, Range( 0f, 10f )] public float DurationSeconds { get; set; } = 6f;
	[Property, Range( 0f, 64f )] public float ExternalMoveTolerance { get; set; } = 1f;

	Vector3 _startPosition;
	Vector3 _targetPosition;
	Vector3 _lastAppliedPosition;
	float _elapsedSeconds;
	bool _active;

	protected override void OnStart()
	{
		_startPosition = WorldPosition;
		_targetPosition = _startPosition + Vector3.Up * LiftDistanceUnits;
		_lastAppliedPosition = _startPosition;
		_elapsedSeconds = 0f;
		_active = MathF.Abs( LiftDistanceUnits ) > 0.001f;

		if ( !_active || DurationSeconds <= 0f )
			FinishAtTarget();
	}

	protected override void OnUpdate()
	{
		if ( !_active )
			return;

		if ( WorldPosition.Distance( _lastAppliedPosition ) > ExternalMoveTolerance )
		{
			_active = false;
			return;
		}

		_elapsedSeconds += Time.Delta;
		var t = (_elapsedSeconds / MathF.Max( 0.001f, DurationSeconds )).Clamp( 0f, 1f );
		var smoothed = SmoothStep( t );

		WorldPosition = Vector3.Lerp( _startPosition, _targetPosition, smoothed );
		_lastAppliedPosition = WorldPosition;

		if ( t >= 1f )
			_active = false;
	}

	static float SmoothStep( float t )
	{
		t = t.Clamp( 0f, 1f );
		return t * t * ( 3f - 2f * t );
	}

	void FinishAtTarget()
	{
		WorldPosition = _targetPosition;
		_lastAppliedPosition = WorldPosition;
		_active = false;
	}
}
