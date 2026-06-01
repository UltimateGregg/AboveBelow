using Sandbox;
using System;
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
	const string DetachedCablePrefabPath = "prefabs/effects/detached_fiber_cable.prefab";

	[Property] public PilotLink Link { get; set; }
	[Property] public LineRenderer Line { get; set; }
	[Property] public Color CableColor { get; set; } = new( 0.62f, 0.64f, 0.66f, 1f );

	/// <summary>
	/// Minimum world-space distance the drone must travel before a new point is
	/// added to the laid-cable trail. Smaller = smoother trail, more points.
	/// </summary>
	[Property, Range( 8f, 200f )] public float TrailSegmentLength { get; set; } = 40f;

	/// <summary>
	/// Target angle for the live cable segment as it rises from the laid trail
	/// to the drone. 45 degrees makes the horizontal lead roughly match height.
	/// </summary>
	[Property, Range( 10f, 85f )] public float DroneLeadAngleDegrees { get; set; } = 45f;

	/// <summary>
	/// Cap for the shifted live lead point so high-altitude flights do not drag
	/// the visual endpoint too far away from the drone.
	/// </summary>
	[Property, Range( 0f, 1200f )] public float DroneLeadMaxHorizontalDistance { get; set; } = 600f;

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
	bool _detachedFromLiveEndpoints;

	protected override void OnStart()
	{
		ResolveRefs();
		ApplyLineStyle();
		_droneTrail.Clear();
		_pilotTrail.Clear();
		_hasLastDroneTrailPoint = false;
		_hasLastPilotTrailPoint = false;
		_detachedFromLiveEndpoints = false;
	}

	protected override void OnUpdate()
	{
		ResolveRefs();
		if ( !Line.IsValid() ) return;
		ApplyLineStyle();
		if ( _detachedFromLiveEndpoints )
			return;

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
		var droneLeadPoint = BuildDroneLeadPoint( dronePos, groundUnderDrone, groundUnderPilot );

		AddTrailPoint( _pilotTrail, groundUnderPilot, ref _lastPilotTrailPoint, ref _hasLastPilotTrailPoint );
		AddTrailPoint( _droneTrail, droneLeadPoint, ref _lastDroneTrailPoint, ref _hasLastDroneTrailPoint );

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
		AddRenderPoint( droneLeadPoint );
		AddRenderPoint( dronePos );

		Line.UseVectorPoints = true;
		Line.VectorPoints = _renderPoints;
	}

	/// <summary>
	/// Leaves the currently unspooled cable on the ground as a standalone local
	/// visual so destroying the drone no longer removes or updates the wire.
	/// </summary>
	public void DetachFromLiveEndpoints()
	{
		ResolveRefs();
		if ( _detachedFromLiveEndpoints || !Line.IsValid() )
			return;

		var frozenPoints = BuildGroundedRenderPoints();
		_detachedFromLiveEndpoints = true;

		if ( frozenPoints.Count < 2 )
		{
			Line.Enabled = false;
			return;
		}

		Line.Enabled = true;
		Line.UseVectorPoints = true;
		Line.VectorPoints = frozenPoints;
		ApplyLineStyle();

		var detachedObject = CreateDetachedCableObject();
		var detachedLine = detachedObject.Components.Get<LineRenderer>( FindMode.EverythingInSelfAndDescendants );
		if ( !detachedLine.IsValid() )
			detachedLine = detachedObject.Components.Create<LineRenderer>();
		ApplyLineStyle( detachedLine, CableColor );
		detachedLine.Enabled = true;
		detachedLine.UseVectorPoints = true;
		detachedLine.VectorPoints = new List<Vector3>( frozenPoints );

		Line.Enabled = false;
	}

	GameObject CreateDetachedCableObject()
	{
		var prefab = GameObject.GetPrefab( DetachedCablePrefabPath );
		if ( prefab.IsValid() )
		{
			var clone = prefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), name: "Detached Fiber Cable" );
			if ( clone.IsValid() )
			{
				clone.NetworkMode = NetworkMode.Never;
				return clone;
			}
		}

		return new GameObject( true, "Detached Fiber Cable" )
		{
			NetworkMode = NetworkMode.Never
		};
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
		AddRenderPoint( _renderPoints, point );
	}

	static void AddRenderPoint( List<Vector3> points, Vector3 point )
	{
		if ( points.Count > 0 && points[points.Count - 1].Distance( point ) < 0.1f )
			return;

		points.Add( point );
	}

	List<Vector3> BuildGroundedRenderPoints()
	{
		var points = new List<Vector3>();
		var pilotPawn = ResolvePilotPawn();
		var leadDirectionReference = _hasLastPilotTrailPoint ? _lastPilotTrailPoint : WorldPosition;
		if ( pilotPawn.IsValid() )
		{
			var groundUnderPilot = SampleGroundBelow( pilotPawn.WorldPosition, pilotPawn.GameObject );
			leadDirectionReference = groundUnderPilot;
			AddRenderPoint( points, groundUnderPilot );
		}
		else if ( _hasLastPilotTrailPoint )
		{
			AddRenderPoint( points, _lastPilotTrailPoint );
		}

		for ( int i = _pilotTrail.Count - 1; i >= 0; i-- )
			AddRenderPoint( points, _pilotTrail[i] );
		for ( int i = 0; i < _droneTrail.Count; i++ )
			AddRenderPoint( points, _droneTrail[i] );

		var groundUnderDrone = SampleGroundBelow( WorldPosition, GameObject );
		AddRenderPoint( points, BuildDroneLeadPoint( WorldPosition, groundUnderDrone, leadDirectionReference ) );
		return points;
	}

	Vector3 BuildDroneLeadPoint( Vector3 dronePos, Vector3 groundUnderDrone, Vector3 groundUnderPilot )
	{
		var verticalDrop = MathF.Max( 0f, dronePos.z - groundUnderDrone.z );
		if ( verticalDrop <= 0.1f )
			return groundUnderDrone;

		var angleRadians = DroneLeadAngleDegrees.Clamp( 10f, 85f ) * (MathF.PI / 180f);
		var horizontalDistance = verticalDrop / MathF.Tan( angleRadians );
		horizontalDistance = MathF.Min( horizontalDistance, MathF.Max( 0f, DroneLeadMaxHorizontalDistance ) );

		if ( horizontalDistance <= 0.1f )
			return groundUnderDrone;

		var direction = ResolveDroneLeadDirection( dronePos, groundUnderDrone, groundUnderPilot );
		var projectedLead = groundUnderDrone + direction * horizontalDistance;
		var leadTraceStart = new Vector3( projectedLead.x, projectedLead.y, MathF.Max( dronePos.z, projectedLead.z ) + 64f );
		return SampleGroundBelow( leadTraceStart, GameObject );
	}

	Vector3 ResolveDroneLeadDirection( Vector3 dronePos, Vector3 groundUnderDrone, Vector3 groundUnderPilot )
	{
		if ( _hasLastDroneTrailPoint )
		{
			var toExistingTrail = FlatDirection( groundUnderDrone, _lastDroneTrailPoint );
			if ( toExistingTrail.Length > 0.001f )
				return toExistingTrail;
		}

		var toPilot = FlatDirection( groundUnderDrone, groundUnderPilot );
		if ( toPilot.Length > 0.001f )
			return toPilot;

		var backward = new Vector3( -WorldRotation.Forward.x, -WorldRotation.Forward.y, 0f );
		if ( backward.Length > 0.001f )
			return backward.Normal;

		var droneOffset = FlatDirection( dronePos, groundUnderDrone );
		if ( droneOffset.Length > 0.001f )
			return droneOffset;

		return new Vector3( -1f, 0f, 0f );
	}

	static Vector3 FlatDirection( Vector3 from, Vector3 to )
	{
		var offset = new Vector3( to.x - from.x, to.y - from.y, 0f );
		return offset.Length > 1f ? offset.Normal : Vector3.Zero;
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
		ApplyLineStyle( Line, CableColor );
	}

	static void ApplyLineStyle( LineRenderer line, Color color )
	{
		if ( !line.IsValid() ) return;

		line.Color = Gradient.FromColors( new[] { color, color } );
		line.Lighting = false;
		line.Additive = false;
		line.Wireframe = false;
		line.CastShadows = false;
	}
}
