using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// World marker for a bright sun glare source. The marker also keeps an
/// additive sprite configured at runtime so the sun stays visible in the sky.
/// </summary>
[Title( "Sun Glare Source" )]
[Category( "Drone vs Players/Game" )]
[Icon( "wb_sunny" )]
public sealed class SunGlareSource : Component
{
	[Property] public string SpriteTexturePath { get; set; } = "materials/skybox/blinding_sun_glow.png";
	[Property] public Vector2 VisualSize { get; set; } = new( 760f, 760f );
	[Property] public Color VisualTint { get; set; } = new( 1f, 0.92f, 0.62f, 1f );

	[Property, Range( 1f, 30f )] public float FullGlareDegrees { get; set; } = 5f;
	[Property, Range( 5f, 60f )] public float OuterGlareDegrees { get; set; } = 24f;
	[Property, Range( 0f, 1f )] public float MaxOpacity { get; set; } = 0.88f;
	[Property] public bool AffectsPilotsOnly { get; set; } = true;
	[Property] public bool GroundPilotViewOnly { get; set; } = true;

	SpriteRenderer _sprite;

	protected override void OnEnabled()
	{
		ConfigureSprite();
	}

	protected override void OnStart()
	{
		ConfigureSprite();
	}

	public float GetGlareOpacity( Vector3 cameraPosition, Vector3 cameraForward, PlayerRole localRole, bool droneViewActive )
	{
		if ( localRole is not (PlayerRole.Pilot or PlayerRole.Soldier) )
			return 0f;

		if ( AffectsPilotsOnly && localRole != PlayerRole.Pilot )
			return 0f;

		if ( GroundPilotViewOnly && droneViewActive )
			return 0f;

		if ( cameraForward.IsNearZeroLength )
			return 0f;

		var toSun = WorldPosition - cameraPosition;
		if ( toSun.IsNearZeroLength )
			return 0f;

		var dot = Vector3.Dot( cameraForward.Normal, toSun.Normal ).Clamp( -1f, 1f );
		var angle = MathF.Acos( dot ) * 57.29578f;

		if ( angle >= OuterGlareDegrees )
			return 0f;

		var falloffSpan = MathF.Max( 0.1f, OuterGlareDegrees - FullGlareDegrees );
		var t = 1f - ((angle - FullGlareDegrees) / falloffSpan).Clamp( 0f, 1f );
		t = t * t * (3f - 2f * t);

		return MaxOpacity * t;
	}

	void ConfigureSprite()
	{
		if ( !_sprite.IsValid() )
			_sprite = Components.Get<SpriteRenderer>() ?? Components.Create<SpriteRenderer>();

		if ( !_sprite.IsValid() )
			return;

		_sprite.Size = VisualSize;
		_sprite.Color = VisualTint;
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
	}
}
