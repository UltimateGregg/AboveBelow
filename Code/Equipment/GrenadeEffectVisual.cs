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
/// Fallback visual feedback for grenade detonations when no effect prefab is
/// wired. It uses small dev-box fragments so the effect remains asset-light and
/// works in plain blockout scenes.
/// </summary>
[Title( "Grenade Effect Visual" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "auto_awesome" )]
public sealed class GrenadeEffectVisual : Component
{
	struct Piece
	{
		public GameObject Object;
		public ModelRenderer Renderer;
		public Vector3 Start;
		public Vector3 Velocity;
		public Rotation BaseRotation;
		public float Spin;
		public Color Color;
	}

	readonly List<Piece> _pieces = new();
	float _spawnTime;
	float _lifetime = 1.5f;
	GrenadeEffectKind _kind;

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
		_kind = kind;
		_spawnTime = Time.Now;
		_lifetime = kind switch
		{
			GrenadeEffectKind.Chaff => 3.0f,
			GrenadeEffectKind.Emp => 2.2f,
			_ => 1.1f
		};

		var count = kind switch
		{
			GrenadeEffectKind.Chaff => 54,
			GrenadeEffectKind.Emp => 36,
			_ => 30
		};

		var color = kind switch
		{
			GrenadeEffectKind.Chaff => new Color( 0.78f, 0.9f, 1f, 0.92f ),
			GrenadeEffectKind.Emp => new Color( 0.18f, 0.9f, 1f, 0.82f ),
			_ => new Color( 1f, 0.48f, 0.14f, 0.95f )
		};

		var maxBurst = MathF.Min( radius * 0.32f, kind == GrenadeEffectKind.Frag ? 180f : 260f );
		var random = new System.Random( GameObject.Id.GetHashCode() );
		var model = Model.Load( "models/dev/box.vmdl" );

		for ( int i = 0; i < count; i++ )
		{
			var child = new GameObject( GameObject, true, "Effect Piece" )
			{
				LocalPosition = RandomOffset( random, kind, maxBurst * 0.14f ),
				LocalRotation = Rotation.From( Rand( random, 0f, 360f ), Rand( random, 0f, 360f ), Rand( random, 0f, 360f ) ),
				LocalScale = RandomScale( random, kind )
			};

			var renderer = child.Components.Create<ModelRenderer>();
			renderer.Model = model;
			renderer.Tint = color;

			_pieces.Add( new Piece
			{
				Object = child,
				Renderer = renderer,
				Start = child.LocalPosition,
				Velocity = RandomOffset( random, kind, maxBurst ) / _lifetime,
				BaseRotation = child.LocalRotation,
				Spin = Rand( random, -540f, 540f ),
				Color = color
			} );
		}
	}

	protected override void OnUpdate()
	{
		var elapsed = Time.Now - _spawnTime;
		var t = (elapsed / _lifetime).Clamp( 0f, 1f );
		var fade = 1f - t;

		for ( int i = 0; i < _pieces.Count; i++ )
		{
			var piece = _pieces[i];
			if ( !piece.Object.IsValid() || !piece.Renderer.IsValid() ) continue;

			var lift = _kind == GrenadeEffectKind.Frag ? Vector3.Up * (60f * MathF.Sin( t * MathF.PI )) : Vector3.Up * (24f * MathF.Sin( t * MathF.PI ));
			piece.Object.LocalPosition = piece.Start + piece.Velocity * elapsed + lift;
			piece.Object.LocalRotation = piece.BaseRotation * Rotation.From( 0f, 0f, elapsed * piece.Spin );
			piece.Renderer.Tint = new Color( piece.Color.r, piece.Color.g, piece.Color.b, piece.Color.a * fade );
		}

		if ( t >= 1f )
			GameObject.Destroy();
	}

	static Vector3 RandomOffset( System.Random random, GrenadeEffectKind kind, float radius )
	{
		var angle = Rand( random, 0f, MathF.PI * 2f );
		var distance = Rand( random, radius * 0.25f, radius );
		var vertical = kind switch
		{
			GrenadeEffectKind.Chaff => Rand( random, 12f, 120f ),
			GrenadeEffectKind.Emp => Rand( random, 4f, 80f ),
			_ => Rand( random, 10f, 150f )
		};

		return new Vector3( MathF.Cos( angle ) * distance, MathF.Sin( angle ) * distance, vertical );
	}

	static Vector3 RandomScale( System.Random random, GrenadeEffectKind kind )
	{
		return kind switch
		{
			GrenadeEffectKind.Chaff => new Vector3( Rand( random, 0.08f, 0.18f ), Rand( random, 0.08f, 0.18f ), Rand( random, 0.02f, 0.05f ) ),
			GrenadeEffectKind.Emp => new Vector3( Rand( random, 0.05f, 0.12f ), Rand( random, 0.05f, 0.12f ), Rand( random, 0.05f, 0.12f ) ),
			_ => new Vector3( Rand( random, 0.08f, 0.2f ), Rand( random, 0.08f, 0.2f ), Rand( random, 0.08f, 0.2f ) )
		};
	}

	static float Rand( System.Random random, float min, float max )
	{
		return min + (float)random.NextDouble() * (max - min);
	}
}
