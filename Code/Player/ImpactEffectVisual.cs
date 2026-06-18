using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Runtime bullet-impact VFX built from the engine's built-in particle
/// components — the same asset-free approach as <see cref="GrenadeEffectVisual"/>,
/// so it needs no authored .vpcf. Surface-aware: orange sparks on metal, a grey
/// dust puff on concrete, brown splinters on wood, a short red mist on flesh.
/// The effect sprays along the surface normal and self-destroys once its burst
/// fades.
///
/// Local-only (<c>NetworkMode.Never</c>). Spawn from inside a weapon's
/// <c>[Rpc.Broadcast]</c> fire handler (via <see cref="ImpactEffects"/>) so every
/// peer sees the hit, not just the shooter.
/// </summary>
[Title( "Impact Effect Visual" )]
[Category( "Drone vs Players/Player" )]
[Icon( "grain" )]
public sealed class ImpactEffectVisual : Component
{
	TimeSince _timeSinceSpawn;
	float _lifetime = 0.6f;
	PointLight _flash;
	float _flashRadius;
	Color _flashColor;

	/// <summary>
	/// Spawn a one-shot impact burst at <paramref name="position"/>, oriented so
	/// particles fly out along <paramref name="normal"/>.
	/// </summary>
	public static void Spawn( Vector3 position, Vector3 normal, ImpactEffects.SurfaceKind kind )
	{
		if ( normal.LengthSquared < 0.001f )
			normal = Vector3.Up;

		var root = new GameObject( true, $"Impact {kind}" )
		{
			NetworkMode = NetworkMode.Never,
			WorldPosition = position,
			WorldRotation = Rotation.LookAt( normal.Normal )
		};

		root.Components.Create<ImpactEffectVisual>().Configure( kind );
	}

	void Configure( ImpactEffects.SurfaceKind kind )
	{
		_timeSinceSpawn = 0f;

		switch ( kind )
		{
			case ImpactEffects.SurfaceKind.Metal:
				_lifetime = 0.45f;
				CreateSparkBurst( "Metal Sparks", new Color( 1f, 0.78f, 0.32f, 1f ), 12, 240f, 0.35f );
				CreateFlash( new Color( 1f, 0.7f, 0.32f, 1f ), 40f );
				break;

			case ImpactEffects.SurfaceKind.Flesh:
				_lifetime = 0.5f;
				CreateMist( "Flesh Mist", new Color( 0.55f, 0.04f, 0.04f, 0.85f ), 14, 0.45f );
				break;

			case ImpactEffects.SurfaceKind.Wood:
				_lifetime = 0.6f;
				CreateSparkBurst( "Wood Splinters", new Color( 0.5f, 0.36f, 0.2f, 1f ), 10, 150f, 0.5f );
				CreateDustPuff( "Wood Dust", new Color( 0.45f, 0.34f, 0.22f, 0.7f ), 8, 0.55f );
				break;

			default: // Concrete / Default
				_lifetime = 0.7f;
				CreateDustPuff( "Concrete Dust", new Color( 0.66f, 0.64f, 0.6f, 0.72f ), 12, 0.6f );
				CreateSparkBurst( "Concrete Chips", new Color( 0.7f, 0.68f, 0.64f, 0.9f ), 6, 120f, 0.45f );
				break;
		}
	}

	// Fast radial debris — sphere emitter, additive for the bright metal case.
	void CreateSparkBurst( string name, Color color, int count, float velocity, float lifetime )
	{
		var child = CreateParticleObject( name, color, 14f, count, lifetime, additive: color.r > 0.85f );
		var emitter = child.Components.Get<ParticleSphereEmitter>() ?? child.Components.Create<ParticleSphereEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.04f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.Radius = 1.5f;
		emitter.Velocity = velocity;
	}

	// Soft puff sprayed forward along the surface normal — cone emitter.
	void CreateDustPuff( string name, Color color, int count, float lifetime )
	{
		var child = CreateParticleObject( name, color, 22f, count, lifetime, additive: false );
		var emitter = child.Components.Get<ParticleConeEmitter>() ?? child.Components.Create<ParticleConeEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.08f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.ConeAngle = 55f;
		emitter.ConeFar = 26f;
		emitter.ConeNear = 1.5f;
		emitter.InVolume = true;
		emitter.VelocityMultiplier = 0.5f;
		emitter.VelocityRandom = 0.5f;
	}

	// Tight low-velocity red spray for body hits.
	void CreateMist( string name, Color color, int count, float lifetime )
	{
		var child = CreateParticleObject( name, color, 12f, count, lifetime, additive: false );
		var emitter = child.Components.Get<ParticleConeEmitter>() ?? child.Components.Create<ParticleConeEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.05f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.ConeAngle = 40f;
		emitter.ConeFar = 18f;
		emitter.ConeNear = 1f;
		emitter.InVolume = true;
		emitter.VelocityMultiplier = 0.7f;
		emitter.VelocityRandom = 0.6f;
	}

	GameObject CreateParticleObject( string name, Color color, float scale, int count, float lifetime, bool additive )
	{
		var child = new GameObject( GameObject, true, name );
		child.LocalPosition = Vector3.Zero;
		child.LocalRotation = Rotation.Identity;

		var effect = child.Components.Get<ParticleEffect>() ?? child.Components.Create<ParticleEffect>();
		effect.MaxParticles = Math.Max( 1, count );
		effect.Lifetime = MathF.Max( 0.05f, lifetime );
		effect.ApplyColor = true;
		effect.ApplyAlpha = true;
		effect.ApplyRotation = true;
		effect.ApplyShape = true;
		effect.Tint = color;
		effect.Brightness = MathF.Max( 1f, color.a * 3f );
		effect.Scale = MathF.Max( 8f, scale );
		effect.Damping = 1.2f;
		effect.LocalSpace = 0f;

		var renderer = child.Components.Get<ParticleSpriteRenderer>() ?? child.Components.Create<ParticleSpriteRenderer>();
		renderer.Additive = additive;
		renderer.Lighting = false;
		renderer.DepthFeather = 16f;
		renderer.Scale = 1f;

		return child;
	}

	void CreateFlash( Color color, float radius )
	{
		var child = new GameObject( GameObject, true, "Impact Flash" );
		child.LocalPosition = Vector3.Zero;

		_flash = child.Components.Create<PointLight>();
		_flash.LightColor = color;
		_flash.Radius = radius;
		_flashRadius = radius;
		_flashColor = color;
	}

	protected override void OnUpdate()
	{
		var t = ((float)_timeSinceSpawn / MathF.Max( 0.05f, _lifetime )).Clamp( 0f, 1f );

		if ( _flash.IsValid() )
		{
			// Metal spark flash punches bright then snaps out over the first third.
			var flashFade = (1f - (t / 0.34f)).Clamp( 0f, 1f );
			_flash.Radius = _flashRadius * flashFade;
			_flash.LightColor = new Color( _flashColor.r, _flashColor.g, _flashColor.b, _flashColor.a * flashFade );
		}

		if ( t >= 1f )
			GameObject.Destroy();
	}
}
