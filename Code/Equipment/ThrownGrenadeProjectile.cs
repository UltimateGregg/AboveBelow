using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Host-simulated grenade body. It traces between positions each frame,
/// bounces or settles on real scene collision, then asks the owning grenade
/// component to detonate from the projectile's current world position.
/// </summary>
[Title( "Thrown Grenade Projectile" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "sports_baseball" )]
public sealed class ThrownGrenadeProjectile : Component
{
	[Property] public Vector3 Velocity { get; set; }
	[Property] public Vector3 Gravity { get; set; } = new( 0f, 0f, 800f );
	[Property] public float FuseSeconds { get; set; } = 1.5f;
	[Property] public float SurfaceRestOffset { get; set; } = 2.5f;
	[Property] public float SpinDegreesPerSecond { get; set; } = 540f;
	[Property] public float BounceDamping { get; set; } = 0.35f;
	[Property] public float MinimumBounceSpeed { get; set; } = 180f;
	[Property] public float MaxLifetime { get; set; } = 8f;

	ThrowableGrenade _owner;
	GameObject _ignoreRoot;
	TimeSince _timeSinceSpawn;
	bool _landed;
	bool _detonated;
	Rotation _baseRotation;

	public void Configure(
		ThrowableGrenade owner,
		GameObject ignoreRoot,
		Vector3 velocity,
		Vector3 gravity,
		float fuseSeconds,
		float surfaceRestOffset,
		float spinDegreesPerSecond )
	{
		_owner = owner;
		_ignoreRoot = ignoreRoot;
		Velocity = velocity;
		Gravity = gravity;
		FuseSeconds = MathF.Max( 0.05f, fuseSeconds );
		SurfaceRestOffset = MathF.Max( 0f, surfaceRestOffset );
		SpinDegreesPerSecond = spinDegreesPerSecond;
		_baseRotation = velocity.IsNearZeroLength ? WorldRotation : Rotation.LookAt( velocity.Normal );
		WorldRotation = _baseRotation;
		_timeSinceSpawn = 0f;
	}

	protected override void OnStart()
	{
		_baseRotation = Velocity.IsNearZeroLength ? WorldRotation : Rotation.LookAt( Velocity.Normal );
	}

	protected override void OnUpdate()
	{
		if ( IsProxy ) return;
		if ( _detonated ) return;

		if ( !_landed )
			MoveProjectile();

		if ( _timeSinceSpawn >= FuseSeconds || _timeSinceSpawn >= MaxLifetime )
			Detonate();
	}

	void MoveProjectile()
	{
		var dt = Time.Delta;
		if ( dt <= 0f ) return;

		var start = WorldPosition;
		var nextVelocity = Velocity - Gravity * dt;
		var end = start + (Velocity + nextVelocity) * 0.5f * dt;

		var trace = Scene.Trace
			.Ray( start, end )
			.WithoutTags( "trigger" );

		if ( _ignoreRoot.IsValid() )
			trace = trace.IgnoreGameObjectHierarchy( _ignoreRoot );

		var tr = trace.Run();
		if ( tr.Hit )
		{
			HandleImpact( tr.HitPosition, tr.Normal, nextVelocity );
			return;
		}

		Velocity = nextVelocity;
		WorldPosition = end;
		UpdateSpin();
	}

	void HandleImpact( Vector3 hitPosition, Vector3 normal, Vector3 incomingVelocity )
	{
		WorldPosition = hitPosition + normal * SurfaceRestOffset;

		var speed = incomingVelocity.Length;
		if ( speed <= MinimumBounceSpeed || normal.z > 0.65f )
		{
			_landed = true;
			Velocity = Vector3.Zero;
			WorldRotation = _baseRotation;
			return;
		}

		var reflected = incomingVelocity - normal * (2f * Vector3.Dot( incomingVelocity, normal ));
		Velocity = reflected * BounceDamping;
		_baseRotation = Velocity.IsNearZeroLength ? WorldRotation : Rotation.LookAt( Velocity.Normal );
		UpdateSpin();
	}

	void UpdateSpin()
	{
		var elapsed = (float)_timeSinceSpawn;
		WorldRotation = _baseRotation * Rotation.From( 0f, 0f, elapsed * SpinDegreesPerSecond );
	}

	void Detonate()
	{
		_detonated = true;

		if ( _owner.IsValid() )
			_owner.ResolveProjectileDetonation( this, WorldPosition );

		GameObject.Destroy();
	}
}
