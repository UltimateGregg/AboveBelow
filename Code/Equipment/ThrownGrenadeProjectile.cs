using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Host-simulated grenade body. Physics owns movement and tumbling; this
/// component owns fuse timing and asks the source grenade to resolve gameplay.
/// </summary>
[Title( "Thrown Grenade Projectile" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "sports_baseball" )]
public sealed class ThrownGrenadeProjectile : Component
{
	[Property] public Rigidbody Body { get; set; }
	[Property] public CapsuleCollider Collider { get; set; }
	[Property] public Vector3 Velocity { get; set; }
	[Property] public Vector3 Gravity { get; set; } = new( 0f, 0f, 800f );
	[Property] public float FuseSeconds { get; set; } = 1.5f;
	[Property] public float MaxLifetime { get; set; } = 8f;
	[Property] public float ColliderRadius { get; set; } = 5.5f;
	[Property] public float ColliderLength { get; set; } = 18f;
	[Property] public float Mass { get; set; } = 1.2f;
	[Property] public float LinearDamping { get; set; } = 0.18f;
	[Property] public float AngularDamping { get; set; } = 0.75f;
	[Property] public float Elasticity { get; set; } = 0.32f;
	[Property] public float Friction { get; set; } = 0.8f;
	[Property] public float RollingResistance { get; set; } = 0.45f;
	[Property, Range( 0f, 20f )] public float SleepThreshold { get; set; } = 2f;
	[Property] public float SpinMin { get; set; } = 420f;
	[Property] public float SpinMax { get; set; } = 980f;
	[Property] public float OwnerCollisionGraceSeconds { get; set; } = 0.12f;

	ThrowableGrenade _owner;
	TimeSince _timeSinceSpawn;
	bool _detonated;

	public void Configure(
		ThrowableGrenade owner,
		GameObject ignoreRoot,
		Vector3 velocity,
		Vector3 gravity,
		float fuseSeconds,
		float colliderRadius,
		float colliderLength,
		float mass,
		float linearDamping,
		float angularDamping,
		float elasticity,
		float friction,
		float rollingResistance,
		float sleepThreshold,
		float spinMin,
		float spinMax,
		float ownerCollisionGraceSeconds )
	{
		_owner = owner;
		Velocity = velocity;
		Gravity = gravity;
		FuseSeconds = MathF.Max( 0.05f, fuseSeconds );
		ColliderRadius = MathF.Max( 1f, colliderRadius );
		ColliderLength = MathF.Max( ColliderRadius * 2f, colliderLength );
		Mass = MathF.Max( 0.05f, mass );
		LinearDamping = MathF.Max( 0f, linearDamping );
		AngularDamping = MathF.Max( 0f, angularDamping );
		Elasticity = MathF.Max( 0f, elasticity );
		Friction = MathF.Max( 0f, friction );
		RollingResistance = MathF.Max( 0f, rollingResistance );
		SleepThreshold = MathF.Max( 0f, sleepThreshold );
		SpinMin = MathF.Max( 0f, MathF.Min( spinMin, spinMax ) );
		SpinMax = MathF.Max( SpinMin, MathF.Max( spinMin, spinMax ) );
		OwnerCollisionGraceSeconds = MathF.Max( 0f, ownerCollisionGraceSeconds );

		if ( !velocity.IsNearZeroLength )
			WorldRotation = Rotation.LookAt( velocity.Normal ) * Rotation.From( 0f, 0f, RandomFloat( 0f, 360f ) );

		_timeSinceSpawn = 0f;

		EnsurePhysicsComponents();
		ConfigurePhysics( true );
	}

	protected override void OnStart()
	{
		EnsurePhysicsComponents();
		ConfigurePhysics( Body.IsValid() && Body.Velocity.IsNearZeroLength && !Velocity.IsNearZeroLength );
	}

	protected override void OnUpdate()
	{
		if ( IsProxy ) return;
		if ( _detonated ) return;

		if ( Collider.IsValid() && Collider.IsTrigger && _timeSinceSpawn >= OwnerCollisionGraceSeconds )
			Collider.IsTrigger = false;

		if ( _timeSinceSpawn >= FuseSeconds || _timeSinceSpawn >= MaxLifetime )
			Detonate();
	}

	protected override void OnFixedUpdate()
	{
		if ( IsProxy ) return;
		if ( Body.IsValid() )
			Velocity = Body.Velocity;
	}

	void EnsurePhysicsComponents()
	{
		Collider ??= Components.Get<CapsuleCollider>();
		if ( !Collider.IsValid() )
			Collider = Components.Create<CapsuleCollider>();

		Body ??= Components.Get<Rigidbody>();
		if ( !Body.IsValid() )
			Body = Components.Create<Rigidbody>();
	}

	void ConfigurePhysics( bool applyInitialVelocity )
	{
		if ( Collider.IsValid() )
		{
			var halfLine = MathF.Max( 0f, ColliderLength * 0.5f - ColliderRadius );
			Collider.Start = new Vector3( -halfLine, 0f, 0f );
			Collider.End = new Vector3( halfLine, 0f, 0f );
			Collider.Radius = ColliderRadius;
			Collider.IsTrigger = OwnerCollisionGraceSeconds > 0f && _timeSinceSpawn < OwnerCollisionGraceSeconds;
			Collider.Friction = Friction;
			Collider.Elasticity = Elasticity;
			Collider.RollingResistance = RollingResistance;
		}

		if ( !Body.IsValid() ) return;

		Body.Gravity = true;
		Body.GravityScale = MathF.Max( 0.05f, Gravity.Length / 800f );
		Body.MassOverride = Mass;
		Body.LinearDamping = LinearDamping;
		Body.AngularDamping = AngularDamping;
		Body.MotionEnabled = true;
		Body.StartAsleep = false;
		Body.EnhancedCcd = true;
		Body.SleepThreshold = SleepThreshold;

		if ( applyInitialVelocity )
		{
			Body.Velocity = Velocity;
			Body.AngularVelocity = RandomAngularVelocity();
		}
	}

	Vector3 RandomAngularVelocity()
	{
		var random = new System.Random( GameObject.Id.GetHashCode() ^ (int)(Time.Now * 1000f) );
		var axis = RandomUnitVector( random );
		var spin = RandomFloat( random, SpinMin, SpinMax );

		if ( !Velocity.IsNearZeroLength )
		{
			var travelAxis = new Vector3( -Velocity.y, Velocity.x, Velocity.z * 0.15f );
			if ( !travelAxis.IsNearZeroLength )
				axis = (axis * 0.45f + travelAxis.Normal * 0.55f).Normal;
		}

		return axis * spin;
	}

	Vector3 RandomUnitVector( System.Random random )
	{
		var z = RandomFloat( random, -1f, 1f );
		var angle = RandomFloat( random, 0f, MathF.PI * 2f );
		var radius = MathF.Sqrt( MathF.Max( 0f, 1f - z * z ) );
		return new Vector3( MathF.Cos( angle ) * radius, MathF.Sin( angle ) * radius, z );
	}

	float RandomFloat( float min, float max )
	{
		return RandomFloat( new System.Random( GameObject.Id.GetHashCode() ^ (int)(Time.Now * 1000f) ), min, max );
	}

	static float RandomFloat( System.Random random, float min, float max )
	{
		return min + (float)random.NextDouble() * (max - min);
	}

	void Detonate()
	{
		_detonated = true;

		if ( _owner.IsValid() )
			_owner.ResolveProjectileDetonation( this, WorldPosition );

		GameObject.Destroy();
	}
}
