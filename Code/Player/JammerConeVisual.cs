using Sandbox;
using System;
using System.Collections.Generic;

namespace DroneVsPlayers;

/// <summary>
/// Local-only particle cone feedback for the counter-UAV jammer.
/// Gameplay jamming still lives in DroneJammerGun; this only renders the
/// visible RF volume.
/// </summary>
[Title( "Jammer Cone Visual" )]
[Category( "Drone vs Players/Effects" )]
[Icon( "wifi_tethering_off" )]
public sealed class JammerConeVisual : Component
{
	const string DefaultTexturePath = "textures/beams/beam_noise05.vtex";

	static readonly string[] FallbackTexturePaths =
	{
		"textures/beams/laser-wobbly.png",
		"textures/beams/soft.png",
		"textures/particles/ring_wave_subtle.vtex",
		"textures/dev/white.vtex"
	};

	[Property] public string PrimaryTexturePath { get; set; } = DefaultTexturePath;
	[Property, Range( 16, 256 )] public int MaxParticles { get; set; } = 96;
	[Property, Range( 0.1f, 1.5f )] public float ParticleLifetime { get; set; } = 0.45f;
	[Property, Range( 10f, 500f )] public float ParticlesPerSecond { get; set; } = 240f;
	[Property, Range( 0.001f, 0.08f )] public float ParticleScalePerRange { get; set; } = 0.024f;
	[Property, Range( 8f, 256f )] public float MinParticleScale { get; set; } = 58f;
	[Property, Range( 16f, 384f )] public float MaxParticleScale { get; set; } = 170f;
	[Property, Range( 0f, 64f )] public float DepthFeather { get; set; } = 28f;
	[Property, Range( 0.1f, 8f )] public float Brightness { get; set; } = 3.4f;
	[Property, Range( 0.05f, 1f )] public float AlphaMultiplier { get; set; } = 0.68f;

	ParticleEffect _effect;
	ParticleConeEmitter _emitter;
	ParticleSpriteRenderer _renderer;
	string _textureRequestKey;
	Vector3 _forward;
	Vector3 _right;
	Vector3 _up;
	float _range;
	float _halfAngle;
	float _emitAccumulator;
	Color _activeColor;
	bool _active;

	protected override void OnStart()
	{
		EnsureComponents();
		Hide();
	}

	public void Configure( Vector3 origin, Vector3 forward, float range, float halfAngle, Color color, bool active )
	{
		EnsureComponents();

		if ( !active || forward.IsNearZeroLength || range <= 0f )
		{
			Hide();
			return;
		}

		WorldPosition = origin;
		_forward = forward.Normal;
		WorldRotation = Rotation.LookAt( _forward, GetStableUp( _forward ) );
		_right = WorldRotation.Right;
		_up = WorldRotation.Up;
		_range = range;
		_halfAngle = halfAngle.Clamp( 1f, 45f );

		var particleScale = (range * ParticleScalePerRange).Clamp( MinParticleScale, MaxParticleScale );
		_activeColor = new Color( color.r, color.g, color.b, (color.a * AlphaMultiplier).Clamp( 0.12f, 0.72f ) );
		_active = true;

		_effect.Enabled = true;
		_effect.MaxParticles = Math.Max( 1, MaxParticles );
		_effect.Lifetime = Math.Max( 0.05f, ParticleLifetime );
		_effect.ApplyColor = true;
		_effect.ApplyAlpha = true;
		_effect.ApplyRotation = true;
		_effect.ApplyShape = true;
		_effect.Tint = _activeColor;
		_effect.Brightness = Math.Max( 0.1f, Brightness );
		_effect.Scale = particleScale;
		_effect.StartVelocity = 0f;
		_effect.Damping = 0.75f;
		_effect.LocalSpace = 0f;
		_effect.Collision = false;

		// Keep an authored cone emitter on the prefab, but emit manually below so
		// the held-weapon effect is visible immediately after input toggles.
		_emitter.Enabled = false;
		_emitter.Loop = true;
		_emitter.DestroyOnEnd = false;
		_emitter.Duration = 1f;
		_emitter.Delay = 0f;
		_emitter.Burst = 0f;
		_emitter.Rate = Math.Max( 1f, ParticlesPerSecond );
		_emitter.RateOverDistance = 0f;
		_emitter.InVolume = true;
		_emitter.OnEdge = false;
		_emitter.ConeAngle = _halfAngle;
		_emitter.ConeNear = Math.Max( 8f, range * 0.015f );
		_emitter.ConeFar = range;
		_emitter.VelocityMultiplier = 0f;
		_emitter.VelocityRandom = 0f;
		_emitter.CenterBias = 0.65f;
		_emitter.CenterBiasVelocity = 0f;

		_renderer.Enabled = true;
		_renderer.Additive = true;
		_renderer.Lighting = false;
		_renderer.Shadows = false;
		_renderer.Opaque = false;
		_renderer.DepthFeather = DepthFeather;
		_renderer.FogStrength = 0.2f;
		_renderer.Scale = 1f;
		_renderer.SortMode = ParticleSpriteRenderer.ParticleSortMode.ByDistance;
		_renderer.Alignment = ParticleSpriteRenderer.BillboardAlignment.LookAtCamera;

		EnsureTexture();
		EmitConeParticles( immediate: _effect.ParticleCount == 0 );
	}

	public void Hide()
	{
		_active = false;
		_emitAccumulator = 0f;
		if ( _emitter.IsValid() )
			_emitter.Enabled = false;
		if ( _renderer.IsValid() )
			_renderer.Enabled = false;
		if ( _effect.IsValid() )
		{
			_effect.Clear();
			_effect.Enabled = false;
		}
	}

	void EnsureComponents()
	{
		_effect = Components.Get<ParticleEffect>( true ) ?? Components.Create<ParticleEffect>();
		_emitter = Components.Get<ParticleConeEmitter>( true ) ?? Components.Create<ParticleConeEmitter>();
		_renderer = Components.Get<ParticleSpriteRenderer>( true ) ?? Components.Create<ParticleSpriteRenderer>();
	}

	protected override void OnUpdate()
	{
		if ( !_active || !_effect.IsValid() || !_renderer.IsValid() )
			return;

		EmitConeParticles();
	}

	void EmitConeParticles( bool immediate = false )
	{
		if ( !_effect.IsValid() || _effect.ParticleCount >= _effect.MaxParticles || _range <= 0f )
			return;

		var wanted = Math.Max( 1f, ParticlesPerSecond ) * Time.Delta;
		if ( immediate )
			wanted += MathF.Min( 18f, Math.Max( 6f, ParticlesPerSecond * 0.08f ) );

		_emitAccumulator += wanted;
		var count = Math.Min( (int)_emitAccumulator, _effect.MaxParticles - _effect.ParticleCount );
		if ( count <= 0 )
			return;

		_emitAccumulator -= count;
		var coneRadians = _halfAngle * (MathF.PI / 180f);
		var tan = MathF.Tan( coneRadians );
		var time = Time.Now;

		for ( int i = 0; i < count; i++ )
		{
			var distanceT = MathF.Pow( Random.Shared.Float( 0.02f, 1f ), 1.55f );
			var distance = MathX.Lerp( MathF.Max( 42f, _range * 0.025f ), _range * 0.82f, distanceT );
			var radius = MathF.Max( 4f, distance * tan );
			var angle = Random.Shared.Float( 0f, MathF.PI * 2f );
			var radialT = MathF.Sqrt( Random.Shared.Float( 0.03f, 1f ) );
			var wave = MathF.Sin( time * 9f + distance * 0.018f + angle * 2.5f ) * radius * 0.16f;
			var lateral = _right * (MathF.Cos( angle ) * radius * radialT + wave)
				+ _up * (MathF.Sin( angle ) * radius * radialT);
			var position = WorldPosition + _forward * distance + lateral;
			var particle = _effect.Emit( position, Time.Delta );

			particle.Color = _activeColor;
			particle.Alpha = _activeColor.a;
			var scale = Random.Shared.Float( 0.72f, 1.18f );
			particle.Size = new Vector3( scale, scale, scale );
			particle.Velocity = _forward * Random.Shared.Float( 24f, 92f )
				+ _right * Random.Shared.Float( -18f, 18f )
				+ _up * Random.Shared.Float( -10f, 24f );
			particle.Angles = new Angles( 0f, 0f, Random.Shared.Float( 0f, 360f ) );
		}
	}

	void EnsureTexture()
	{
		var requestKey = PrimaryTexturePath ?? "";
		if ( _renderer.Sprite is not null && _textureRequestKey == requestKey )
			return;

		_textureRequestKey = requestKey;
		foreach ( var path in GetTexturePaths() )
		{
			var texture = Texture.Load( path, true );
			if ( texture is null || !texture.IsValid || texture.IsError )
				continue;

			_renderer.Sprite = Sprite.FromTexture( texture );
			return;
		}

		_renderer.Sprite = Sprite.FromTexture( Texture.White );
	}

	IEnumerable<string> GetTexturePaths()
	{
		if ( !string.IsNullOrWhiteSpace( PrimaryTexturePath ) )
			yield return PrimaryTexturePath;

		foreach ( var path in FallbackTexturePaths )
			yield return path;
	}

	static Vector3 GetStableUp( Vector3 forward )
	{
		return MathF.Abs( Vector3.Dot( forward, Vector3.Up ) ) > 0.95f
			? Vector3.Right
			: Vector3.Up;
	}
}
