using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Lightweight client-side arc animator kept for non-authoritative throw FX.
/// Live grenade gameplay now uses <see cref="ThrownGrenadeProjectile"/>.
/// </summary>
[Title( "Thrown Grenade Visual" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "sports_baseball" )]
public sealed class ThrownGrenadeVisual : Component
{
	[Property] public float SpinDegreesPerSecond { get; set; } = 540f;

	Vector3 _start;
	Vector3 _end;
	float _duration = 0.1f;
	float _arcHeight = 120f;
	float _spawnTime;
	Rotation _baseRotation;
	bool _configured;

	/// <summary>
	/// Starts a visual-only grenade arc. The object destroys itself when the
	/// arc reaches its configured end point.
	/// </summary>
	public void Configure( Vector3 start, Vector3 end, float duration, float arcHeight )
	{
		_start = start;
		_end = end;
		_duration = MathF.Max( 0.05f, duration );
		_arcHeight = MathF.Max( 0f, arcHeight );
		_spawnTime = Time.Now;

		var travel = _end - _start;
		_baseRotation = travel.IsNearZeroLength
			? WorldRotation
			: Rotation.LookAt( travel.Normal );

		WorldPosition = _start;
		WorldRotation = _baseRotation;
		_configured = true;
	}

	protected override void OnStart()
	{
		if ( _configured ) return;

		_start = WorldPosition;
		_end = WorldPosition;
		_spawnTime = Time.Now;
		_baseRotation = WorldRotation;
	}

	protected override void OnUpdate()
	{
		var elapsed = Time.Now - _spawnTime;
		var t = (elapsed / _duration).Clamp( 0f, 1f );
		var arc = MathF.Sin( t * MathF.PI ) * _arcHeight;

		WorldPosition = Vector3.Lerp( _start, _end, t ) + Vector3.Up * arc;
		WorldRotation = _baseRotation * Rotation.From( 0f, 0f, elapsed * SpinDegreesPerSecond );

		if ( t >= 1f )
			GameObject.Destroy();
	}
}
