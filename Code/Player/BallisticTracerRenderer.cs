using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Lightweight local-only ballistic tracer backed by a SceneLineObject. Weapons
/// use this when no explicit tracer prefab is configured.
/// </summary>
[Title( "Ballistic Tracer Renderer" )]
[Category( "Drone vs Players/Player" )]
[Icon( "show_chart" )]
public sealed class BallisticTracerRenderer : Component, Component.ITemporaryEffect
{
	const string DefaultPrefabPath = "prefabs/effects/ballistic_tracer.prefab";

	[Property, Range( 0.02f, 0.35f )] public float Lifetime { get; set; } = 0.09f;
	[Property, Range( 0.01f, 0.20f )] public float TravelSeconds { get; set; } = 0.045f;
	[Property, Range( 24f, 220f )] public float TracerLength { get; set; } = 95f;
	[Property, Range( 0.2f, 8f )] public float HeadWidth { get; set; } = 2.1f;
	[Property, Range( 0.1f, 6f )] public float TailWidth { get; set; } = 0.65f;
	[Property] public Color TailColor { get; set; } = new( 1f, 0.45f, 0.05f, 0.05f );
	[Property] public Color HotColor { get; set; } = new( 1f, 0.88f, 0.24f, 0.9f );

	SceneLineObject _line;
	TimeSince _timeSinceSpawn;
	Vector3 _from;
	Vector3 _direction = Vector3.Forward;
	float _distance;
	float _scale = 1f;
	bool _configured;
	bool _disabled;

	public bool IsActive => !_disabled && _timeSinceSpawn < Lifetime;

	public static void Spawn( Scene scene, Vector3 from, Vector3 to, float scale = 1f )
	{
		var path = to - from;
		if ( path.Length < 1f )
			return;

		var rotation = Rotation.LookAt( path.Normal );
		var prefab = GameObject.GetPrefab( DefaultPrefabPath );
		if ( prefab.IsValid() )
		{
			var clone = prefab.Clone( new Transform( from, rotation ), name: "Ballistic Tracer" );
			clone.NetworkMode = NetworkMode.Never;
			var prefabTracer = clone.Components.Get<BallisticTracerRenderer>( FindMode.EverythingInSelfAndDescendants );
			if ( prefabTracer.IsValid() )
			{
				prefabTracer.Configure( from, to, scale );
				return;
			}

			clone.Destroy();
		}

		var tracerObject = new GameObject( true, "Ballistic Tracer" )
		{
			NetworkMode = NetworkMode.Never,
			WorldPosition = from,
			WorldRotation = rotation
		};

		var tracer = tracerObject.Components.Create<BallisticTracerRenderer>();
		tracer.Configure( from, to, scale );
	}

	public void Configure( Vector3 from, Vector3 to, float scale = 1f )
	{
		_from = from;
		var path = to - from;
		_distance = path.Length;
		_direction = _distance > 0.01f ? path / _distance : Vector3.Forward;
		_scale = MathF.Max( 0.1f, scale );
		_timeSinceSpawn = 0f;
		_configured = _distance > 0.01f;
		_disabled = false;

		UpdateLine();
	}

	protected override void OnUpdate()
	{
		if ( !_configured || _disabled )
		{
			GameObject.Destroy();
			return;
		}

		UpdateLine();

		if ( _timeSinceSpawn >= Lifetime )
			GameObject.Destroy();
	}

	protected override void OnDestroy()
	{
		_line?.Delete();
		_line = null;
	}

	public void DisableLooping()
	{
		_disabled = true;
	}

	void EnsureLine()
	{
		if ( _line is not null )
			return;

		var sceneWorld = Scene?.SceneWorld;
		if ( sceneWorld is null )
			return;

		_line = new SceneLineObject( sceneWorld )
		{
			Lighting = false,
			Opaque = false,
			Smoothness = 2,
			TessellationLevel = 2
		};
	}

	void UpdateLine()
	{
		EnsureLine();
		if ( _line is null )
			return;

		var elapsed = (float)_timeSinceSpawn;
		var travelT = TravelSeconds <= 0f ? 1f : (elapsed / TravelSeconds).Clamp( 0f, 1f );
		var fade = 1f - (elapsed / MathF.Max( Lifetime, 0.001f )).Clamp( 0f, 1f );
		var headDistance = _distance * travelT;
		var tailDistance = MathF.Max( 0f, headDistance - TracerLength * _scale );
		var tail = _from + _direction * tailDistance;
		var head = _from + _direction * headDistance;
		var tailColor = new Color( TailColor.r, TailColor.g, TailColor.b, TailColor.a * fade );
		var hotColor = new Color( HotColor.r, HotColor.g, HotColor.b, HotColor.a * fade );

		_line.Clear();
		_line.StartLine();
		_line.AddLinePoint( tail, tailColor, TailWidth * _scale, 0f );
		_line.AddLinePoint( head, hotColor, HeadWidth * _scale, 1f );
		_line.EndLine();
		_line.RenderSceneObject();
	}
}
