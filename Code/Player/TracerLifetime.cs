using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Animates and destroys a short visual bullet tracer. Damage is still handled
/// by the weapon's authoritative hitscan; this component only moves the yellow
/// streak that leaves the muzzle.
/// </summary>
[Title( "Tracer Lifetime" )]
[Category( "Drone vs Players/Player" )]
[Icon( "show_chart" )]
public sealed class TracerLifetime : Component
{
	const string DefaultGlowTexture = "materials/skybox/blinding_sun_glow.png";

	[Property, Range( 0.02f, 1.0f )] public float Lifetime { get; set; } = 0.08f;
	[Property, Range( 8f, 180f )] public float TracerLength { get; set; } = 70f;
	[Property, Range( 0.01f, 0.2f )] public float TravelSeconds { get; set; } = 0.055f;
	[Property] public Color TailColor { get; set; } = new( 1f, 0.55f, 0.05f, 0.15f );
	[Property] public Color HotColor { get; set; } = new( 1f, 0.9f, 0.28f, 0.95f );
	[Property] public Vector2 BulletGlowSize { get; set; } = new( 5f, 5f );
	[Property] public string BulletGlowTexturePath { get; set; } = DefaultGlowTexture;

	LineRenderer _line;
	SpriteRenderer _bulletGlow;
	TimeSince _timeSinceSpawn;
	Vector3 _from;
	Vector3 _direction;
	float _distance;
	bool _configured;

	/// <summary>
	/// Sets the world-space bullet path this visual tracer should travel along.
	/// </summary>
	public void Configure( Vector3 from, Vector3 to )
	{
		_timeSinceSpawn = 0f;
		_from = from;

		var path = to - from;
		_distance = path.Length;
		_direction = _distance > 0.01f ? path / _distance : Vector3.Forward;
		_configured = _distance > 0.01f;

		ApplyTracerVisuals();
		UpdateBulletVisual( 0f );
	}

	protected override void OnStart()
	{
		_timeSinceSpawn = 0f;
		ApplyTracerVisuals();
	}

	protected override void OnUpdate()
	{
		if ( _configured )
			UpdateBulletVisual( (float)_timeSinceSpawn );

		if ( _timeSinceSpawn >= Lifetime )
			GameObject.Destroy();
	}

	void ApplyTracerVisuals()
	{
		if ( !_line.IsValid() )
			_line = Components.Get<LineRenderer>();

		if ( _line.IsValid() )
			_line.Color = Gradient.FromColors( new[] { TailColor, HotColor } );

		if ( !_bulletGlow.IsValid() )
		{
			var glowObject = new GameObject( GameObject, true, "Bullet Glow" );
			_bulletGlow = glowObject.Components.Create<SpriteRenderer>();
		}

		if ( !_bulletGlow.IsValid() )
			return;

		_bulletGlow.Size = BulletGlowSize;
		_bulletGlow.Color = HotColor;
		_bulletGlow.Additive = true;
		_bulletGlow.Shadows = false;
		_bulletGlow.Opaque = false;
		_bulletGlow.Lighting = false;
		_bulletGlow.FogStrength = 0f;
		_bulletGlow.Billboard = SpriteRenderer.BillboardMode.Always;
		_bulletGlow.IsSorted = false;

		var texture = Texture.Load( BulletGlowTexturePath, true );
		if ( texture is not null && texture.IsValid )
			_bulletGlow.Sprite = Sprite.FromTexture( texture );
	}

	void UpdateBulletVisual( float elapsed )
	{
		if ( !_line.IsValid() )
			_line = Components.Get<LineRenderer>();

		var travelT = TravelSeconds <= 0f ? 1f : (elapsed / TravelSeconds).Clamp( 0f, 1f );
		var headDistance = _distance * travelT;
		var tailDistance = MathF.Max( 0f, headDistance - TracerLength );
		var tail = _from + _direction * tailDistance;
		var head = _from + _direction * headDistance;
		var fade = 1f - (elapsed / MathF.Max( Lifetime, 0.001f )).Clamp( 0f, 1f );

		if ( _line.IsValid() )
		{
			_line.UseVectorPoints = true;
			_line.VectorPoints = new System.Collections.Generic.List<Vector3> { tail, head };
		}

		if ( _bulletGlow.IsValid() )
		{
			_bulletGlow.GameObject.WorldPosition = head;
			_bulletGlow.Color = new Color( HotColor.r, HotColor.g, HotColor.b, HotColor.a * fade );
		}
	}
}
