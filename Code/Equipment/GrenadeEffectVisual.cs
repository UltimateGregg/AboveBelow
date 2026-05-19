using Sandbox;
using System;
using System.Collections.Generic;

namespace DroneVsPlayers;

public enum GrenadeEffectKind
{
	Chaff,
	Emp,
	Frag
}

/// <summary>
/// Typed fallback feedback for grenade detonations when no stock effect prefab
/// is available. The primary path should still be a wired prefab; this keeps
/// playtests readable if a mounted stock asset cannot be loaded.
/// </summary>
[Title( "Grenade Effect Visual" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "auto_awesome" )]
public sealed class GrenadeEffectVisual : Component
{
	struct LightPulse
	{
		public PointLight Light;
		public float Radius;
		public Color Color;
	}

	readonly List<LightPulse> _lights = new();
	TimeSince _timeSinceSpawn;
	float _lifetime = 1.5f;

	public static void Spawn( Vector3 center, GrenadeEffectKind kind, float radius )
	{
		var root = new GameObject( true, $"{kind} Grenade Effect" )
		{
			NetworkMode = NetworkMode.Never,
			WorldPosition = center
		};

		var visual = root.Components.Create<GrenadeEffectVisual>();
		visual.Configure( kind, radius );
	}

	void Configure( GrenadeEffectKind kind, float radius )
	{
		_timeSinceSpawn = 0f;
		_lifetime = kind switch
		{
			GrenadeEffectKind.Chaff => 2.8f,
			GrenadeEffectKind.Emp => 1.7f,
			_ => 1.3f
		};

		switch ( kind )
		{
			case GrenadeEffectKind.Chaff:
				CreateSmokeBurst( "Chaff Smoke", new Color( 0.72f, 0.86f, 0.95f, 0.75f ), radius * 0.28f, 54, 2.6f );
				CreateSparkBurst( "Chaff Metallic Flash", new Color( 0.9f, 0.97f, 1f, 0.95f ), radius * 0.18f, 32, 0.55f );
				CreateLightPulse( new Color( 0.6f, 0.9f, 1f, 1f ), MathF.Min( radius * 0.45f, 320f ) );
				break;
			case GrenadeEffectKind.Emp:
				CreateRingBurst( "EMP Ring", new Color( 0.18f, 0.9f, 1f, 0.9f ), radius * 0.42f, 18, 0.9f );
				CreateSparkBurst( "EMP Spark Pulse", new Color( 0.35f, 0.95f, 1f, 1f ), radius * 0.24f, 44, 0.7f );
				CreateLightPulse( new Color( 0.1f, 0.78f, 1f, 1f ), MathF.Min( radius * 0.55f, 620f ) );
				break;
			default:
				CreateFlashBurst( "Frag Fireball", new Color( 1f, 0.48f, 0.12f, 0.95f ), radius * 0.24f, 18, 0.45f );
				CreateSmokeBurst( "Frag Smoke", new Color( 0.28f, 0.26f, 0.23f, 0.72f ), radius * 0.32f, 38, 1.4f );
				CreateSparkBurst( "Frag Sparks", new Color( 1f, 0.72f, 0.24f, 1f ), radius * 0.2f, 26, 0.65f );
				CreateLightPulse( new Color( 1f, 0.45f, 0.16f, 1f ), MathF.Min( radius * 0.7f, 360f ) );
				break;
		}
	}

	void CreateFlashBurst( string name, Color color, float scale, int count, float lifetime )
	{
		var child = CreateParticleObject( name, color, scale, count, lifetime );
		var emitter = child.Components.Create<ParticleSphereEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.08f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.Radius = MathF.Max( 2f, scale * 0.05f );
		emitter.Velocity = MathF.Max( 80f, scale * 1.8f );
	}

	void CreateSmokeBurst( string name, Color color, float scale, int count, float lifetime )
	{
		var child = CreateParticleObject( name, color, scale, count, lifetime );
		var emitter = child.Components.Create<ParticleConeEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.12f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.ConeAngle = 70f;
		emitter.ConeFar = MathF.Max( 24f, scale * 0.35f );
		emitter.ConeNear = 2f;
		emitter.InVolume = true;
		emitter.VelocityMultiplier = 0.55f;
		emitter.VelocityRandom = 0.5f;
	}

	void CreateSparkBurst( string name, Color color, float scale, int count, float lifetime )
	{
		var child = CreateParticleObject( name, color, scale, count, lifetime );
		var emitter = child.Components.Create<ParticleSphereEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.05f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.Radius = MathF.Max( 1f, scale * 0.02f );
		emitter.Velocity = MathF.Max( 180f, scale * 2.8f );
	}

	void CreateRingBurst( string name, Color color, float scale, int count, float lifetime )
	{
		var child = CreateParticleObject( name, color, scale, count, lifetime );
		child.LocalRotation = Rotation.From( 90f, 0f, 0f );

		var emitter = child.Components.Create<ParticleConeEmitter>();
		emitter.Burst = count;
		emitter.Duration = 0.06f;
		emitter.Loop = false;
		emitter.DestroyOnEnd = true;
		emitter.ConeAngle = 88f;
		emitter.ConeFar = MathF.Max( 60f, scale * 0.5f );
		emitter.ConeNear = MathF.Max( 12f, scale * 0.12f );
		emitter.OnEdge = true;
		emitter.VelocityMultiplier = 1.1f;
	}

	GameObject CreateParticleObject( string name, Color color, float scale, int count, float lifetime )
	{
		var child = new GameObject( GameObject, true, name )
		{
			LocalPosition = Vector3.Zero
		};

		var effect = child.Components.Create<ParticleEffect>();
		effect.MaxParticles = Math.Max( 1, count );
		effect.Lifetime = MathF.Max( 0.05f, lifetime );
		effect.ApplyColor = true;
		effect.ApplyAlpha = true;
		effect.ApplyRotation = true;
		effect.ApplyShape = true;
		effect.Tint = color;
		effect.Brightness = MathF.Max( 1f, color.a * 3f );
		effect.Scale = MathF.Max( 16f, scale );
		effect.Damping = 0.5f;
		effect.LocalSpace = 0f;

		var renderer = child.Components.Create<ParticleSpriteRenderer>();
		renderer.Additive = color.r > 0.75f || color.b > 0.75f;
		renderer.Lighting = false;
		renderer.DepthFeather = 24f;
		renderer.Scale = 1f;

		return child;
	}

	void CreateLightPulse( Color color, float radius )
	{
		var child = new GameObject( GameObject, true, "Explosion Light" );
		var light = child.Components.Create<PointLight>();
		light.LightColor = color;
		light.Radius = MathF.Max( 64f, radius );

		_lights.Add( new LightPulse
		{
			Light = light,
			Radius = light.Radius,
			Color = color
		} );
	}

	protected override void OnUpdate()
	{
		var t = ((float)_timeSinceSpawn / MathF.Max( 0.05f, _lifetime )).Clamp( 0f, 1f );
		var fade = 1f - t;

		for ( int i = 0; i < _lights.Count; i++ )
		{
			var pulse = _lights[i];
			if ( !pulse.Light.IsValid() ) continue;

			pulse.Light.Radius = pulse.Radius * fade;
			pulse.Light.LightColor = new Color( pulse.Color.r, pulse.Color.g, pulse.Color.b, pulse.Color.a * fade );
		}

		if ( t >= 1f )
			GameObject.Destroy();
	}
}
