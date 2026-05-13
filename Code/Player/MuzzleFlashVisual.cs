using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Short-lived additive muzzle flash spawned by weapon fire RPCs.
/// </summary>
[Title( "Muzzle Flash Visual" )]
[Category( "Drone vs Players/Player" )]
[Icon( "flare" )]
public sealed class MuzzleFlashVisual : Component
{
	const string DefaultSpriteTexture = "materials/skybox/blinding_sun_glow.png";

	[Property, Range( 0.02f, 0.2f )] public float Lifetime { get; set; } = 0.055f;
	[Property] public string SpriteTexturePath { get; set; } = DefaultSpriteTexture;
	[Property] public Vector2 StartSize { get; set; } = new( 42f, 32f );
	[Property] public Vector2 EndSize { get; set; } = new( 72f, 54f );
	[Property] public Color FlashColor { get; set; } = new( 1f, 0.72f, 0.18f, 0.95f );
	[Property] public float LightRadius { get; set; } = 150f;

	SpriteRenderer _sprite;
	PointLight _light;
	TimeSince _timeSinceSpawn;
	float _scale = 1f;
	bool _spriteConfigured;

	/// <summary>
	/// Creates a local-only muzzle flash at the fired weapon's muzzle.
	/// </summary>
	public static void Spawn( Vector3 origin, Vector3 direction, float scale = 1f )
	{
		if ( direction.IsNearZeroLength )
			return;

		var dir = direction.Normal;
		var flashObject = new GameObject( true, "Muzzle Flash" )
		{
			WorldPosition = origin + dir * 10f,
			WorldRotation = Rotation.LookAt( dir )
		};

		var flash = flashObject.Components.Create<MuzzleFlashVisual>();
		flash.Configure( scale );
	}

	/// <summary>
	/// Sets the size multiplier before the flash begins fading out.
	/// </summary>
	public void Configure( float scale )
	{
		_scale = MathF.Max( 0.1f, scale );
		ConfigureRenderers();
	}

	protected override void OnStart()
	{
		_timeSinceSpawn = 0f;
		ConfigureRenderers();
	}

	protected override void OnUpdate()
	{
		ConfigureRenderers();

		var t = Lifetime <= 0f ? 1f : ((float)_timeSinceSpawn / Lifetime).Clamp( 0f, 1f );
		var fade = 1f - t;

		if ( _sprite.IsValid() )
		{
			_sprite.Size = LerpSize( StartSize, EndSize, t ) * _scale;
			_sprite.Color = new Color( FlashColor.r, FlashColor.g, FlashColor.b, FlashColor.a * fade );
		}

		if ( _light.IsValid() )
		{
			_light.Enabled = fade > 0.01f;
			_light.Radius = LightRadius * _scale * fade;
			_light.LightColor = new Color( 1f, 0.62f, 0.22f, fade );
		}

		if ( t >= 1f )
			GameObject.Destroy();
	}

	void ConfigureRenderers()
	{
		if ( !_sprite.IsValid() )
		{
			_sprite = Components.Get<SpriteRenderer>() ?? Components.Create<SpriteRenderer>();
			_spriteConfigured = false;
		}

		if ( _sprite.IsValid() && !_spriteConfigured )
		{
			_sprite.Additive = true;
			_sprite.Shadows = false;
			_sprite.Opaque = false;
			_sprite.Lighting = false;
			_sprite.FogStrength = 0f;
			_sprite.Billboard = SpriteRenderer.BillboardMode.Always;
			_sprite.IsSorted = false;

			var texture = Texture.Load( SpriteTexturePath, true );
			if ( texture is not null && texture.IsValid )
				_sprite.Sprite = Sprite.FromTexture( texture );

			_spriteConfigured = true;
		}

		if ( !_light.IsValid() )
			_light = Components.Get<PointLight>() ?? Components.Create<PointLight>();
	}

	static Vector2 LerpSize( Vector2 start, Vector2 end, float t )
	{
		return new Vector2(
			MathX.Lerp( start.x, end.x, t ),
			MathX.Lerp( start.y, end.y, t ) );
	}
}
