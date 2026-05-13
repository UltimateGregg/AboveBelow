using Sandbox;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Visual-only tether between a fiber-optic FPV drone and its pilot. The fiber
/// is modeled as a thin trail of points laid on the ground as the drone flies,
/// emulating real-world fiber-optic FPV drones that unspool fiber from the
/// drone and pilot, leaving it on the terrain behind them. The cable goes:
///   pilot position -> pilot's walked trail -> drone's laid trail -> drone
///
/// Visual styling is enforced here so prefab/editor defaults cannot make the
/// cable inherit the bright blue LineRenderer color.
/// </summary>
[Title( "Fiber Cable" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "timeline" )]
public sealed class FiberCable : Component
{
	[Property] public PilotLink Link { get; set; }
	[Property] public LineRenderer Line { get; set; }
	[Property] public Color CableColor { get; set; } = new( 0.62f, 0.64f, 0.66f, 1f );

	/// <summary>
	/// Minimum world-space distance the drone must travel before a new point is
	/// added to the laid-cable trail. Smaller = smoother trail, more points.
	/// </summary>
	[Property, Range( 8f, 200f )] public float TrailSegmentLength { get; set; } = 40f;

	/// <summary>
	/// Hard cap on trail point count to keep the LineRenderer cheap on long
	/// flights. Applied separately to pilot and drone trails.
	/// </summary>
	[Property, Range( 16, 1024 )] public int MaxTrailPoints { get; set; } = 256;

	/// <summary>
	/// How far above the hit surface the cable sits. Avoids z-fighting with
	/// terrain meshes while still reading as "lying on the ground".
	/// </summary>
	[Property, Range( 0f, 5f )] public float GroundOffset { get; set; } = 0.5f;

	/// <summary>
	/// If a downward trace from the drone misses (e.g. flying out over a void),
	/// drop the cable point this far below the drone instead.
	/// </summary>
	[Property] public float MaxDropDistance { get; set; } = 2000f;

	readonly List<Vector3> _droneTrail = new();
	readonly List<Vector3> _pilotTrail = new();
	readonly List<Vector3> _renderPoints = new();
	Vector3 _lastDroneTrailPoint;
	Vector3 _lastPilotTrailPoint;
	bool _hasLastDroneTrailPoint;
	bool _hasLastPilotTrailPoint;

	protected override void OnStart()
	{
		ResolveRefs();
		ApplyLineStyle();
		_droneTrail.Clear();
		_pilotTrail.Clear();
		_hasLastDroneTrailPoint = false;
		_hasLastPilotTrailPoint = false;
	}

	protected override void OnUpdate()
	{
		ResolveRefs();
		if ( !Line.IsValid() ) return;
		ApplyLineStyle();

		var pilotPawn = ResolvePilotPawn();
		if ( !pilotPawn.IsValid() )
		{
			Line.Enabled = false;
			return;
		}

		Line.Enabled = true;

		var pilotPos = pilotPawn.WorldPosition;
		var groundUnderPilot = SampleGroundBelow( pilotPos, pilotPawn.GameObject );

		// Sample ground beneath the drone for this frame's "where is the cable
		// touching the ground" point.
		var dronePos = WorldPosition;
		var groundUnderDrone = SampleGroundBelow( dronePos, GameObject );

		AddTrailPoint( _pilotTrail, groundUnderPilot, ref _lastPilotTrailPoint, ref _hasLastPilotTrailPoint );
		AddTrailPoint( _droneTrail, groundUnderDrone, ref _lastDroneTrailPoint, ref _hasLastDroneTrailPoint );

		// Build polyline from live pilot to live drone. Pilot trail is walked
		// backward from newest to oldest, then drone trail continues oldest to
		// newest toward the drone.
		_renderPoints.Clear();
		AddRenderPoint( pilotPos );
		AddRenderPoint( groundUnderPilot );
		for ( int i = _pilotTrail.Count - 1; i >= 0; i-- )
			AddRenderPoint( _pilotTrail[i] );
		for ( int i = 0; i < _droneTrail.Count; i++ )
			AddRenderPoint( _droneTrail[i] );
		AddRenderPoint( dronePos );

		Line.UseVectorPoints = true;
		Line.VectorPoints = _renderPoints;
	}

	PilotSoldier ResolvePilotPawn()
	{
		if ( !Link.IsValid() || Link.PilotId == default ) return null;
		return Scene.GetAllComponents<PilotSoldier>()
			.FirstOrDefault( p => p.GameObject.Network.Owner?.Id == Link.PilotId );
	}

	void AddTrailPoint( List<Vector3> trail, Vector3 point, ref Vector3 lastPoint, ref bool hasLastPoint )
	{
		if ( hasLastPoint && lastPoint.Distance( point ) < TrailSegmentLength )
			return;

		trail.Add( point );
		lastPoint = point;
		hasLastPoint = true;

		if ( trail.Count > MaxTrailPoints )
			trail.RemoveAt( 0 );
	}

	void AddRenderPoint( Vector3 point )
	{
		if ( _renderPoints.Count > 0 && _renderPoints[_renderPoints.Count - 1].Distance( point ) < 0.1f )
			return;

		_renderPoints.Add( point );
	}

	Vector3 SampleGroundBelow( Vector3 from, GameObject ignore )
	{
		// Trace straight down, ignoring actor hierarchies so we don't hit the
		// drone or pilot body collider while finding the ground.
		var query = Scene.Trace.Ray( from, from + Vector3.Down * MaxDropDistance )
			.IgnoreGameObjectHierarchy( GameObject );

		if ( ignore.IsValid() && ignore != GameObject )
			query = query.IgnoreGameObjectHierarchy( ignore );

		var trace = query.Run();

		if ( trace.Hit )
			return trace.HitPosition + Vector3.Up * GroundOffset;

		// Fallback: project to a sensible "below the drone" point if there's
		// no surface (e.g. drone is over an open void).
		return new Vector3( from.x, from.y, from.z - MaxDropDistance );
	}

	void ResolveRefs()
	{
		if ( !Link.IsValid() )
			Link = Components.Get<PilotLink>();
		if ( !Line.IsValid() )
			Line = Components.Get<LineRenderer>();
	}

	void ApplyLineStyle()
	{
		if ( !Line.IsValid() ) return;

		Line.Color = Gradient.FromColors( new[] { CableColor, CableColor } );
		Line.Lighting = false;
		Line.Additive = false;
		Line.Wireframe = false;
		Line.CastShadows = false;
	}
}
