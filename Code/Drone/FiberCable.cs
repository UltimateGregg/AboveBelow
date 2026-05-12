using Sandbox;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Visual-only tether between a fiber-optic FPV drone and its pilot. The fiber
/// is modeled as a thin trail of points laid on the ground as the drone flies,
/// emulating real-world fiber-optic FPV drones that unspool fiber from the
/// drone, leaving it on the terrain behind. The cable goes:
///   pilot position → laid trail points (history of drone's ground projection)
///   → straight up to drone
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
	/// flights. Older points get dropped from the drone end (closest to drone)
	/// once the cap is hit, simulating fiber being reeled in from the slack.
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

	readonly List<Vector3> _trail = new();
	readonly List<Vector3> _renderPoints = new();
	Vector3 _lastTrailPoint;
	bool _hasLastTrailPoint;

	protected override void OnStart()
	{
		ResolveRefs();
		ApplyLineStyle();
		_trail.Clear();
		_hasLastTrailPoint = false;
	}

	protected override void OnUpdate()
	{
		ResolveRefs();
		if ( !Line.IsValid() ) return;
		ApplyLineStyle();

		var pilotPos = ResolvePilotPosition();
		if ( !pilotPos.HasValue )
		{
			Line.Enabled = false;
			return;
		}

		Line.Enabled = true;

		// Sample ground beneath the drone for this frame's "where is the cable
		// touching the ground" point.
		var dronePos = WorldPosition;
		var groundUnderDrone = SampleGroundBelow( dronePos );

		// Add to trail when the drone's ground projection has moved enough
		// from the last laid point. First sample always seeds the trail.
		if ( !_hasLastTrailPoint || _lastTrailPoint.Distance( groundUnderDrone ) >= TrailSegmentLength )
		{
			_trail.Add( groundUnderDrone );
			_lastTrailPoint = groundUnderDrone;
			_hasLastTrailPoint = true;

			// Cap from the front — the point closest to the pilot is "fiber
			// already paid out", oldest data, safe to drop. Drone-end stays.
			if ( _trail.Count > MaxTrailPoints )
				_trail.RemoveAt( 0 );
		}

		// Build polyline: pilot at one end, trail points in the order they
		// were laid (oldest → newest), straight segment up to the drone.
		_renderPoints.Clear();
		_renderPoints.Add( pilotPos.Value );
		for ( int i = 0; i < _trail.Count; i++ )
			_renderPoints.Add( _trail[i] );
		_renderPoints.Add( dronePos );

		Line.UseVectorPoints = true;
		Line.VectorPoints = _renderPoints;
	}

	Vector3? ResolvePilotPosition()
	{
		if ( !Link.IsValid() || Link.PilotId == default ) return null;
		var pilotPawn = Scene.GetAllComponents<PilotSoldier>()
			.FirstOrDefault( p => p.GameObject.Network.Owner?.Id == Link.PilotId );
		return pilotPawn.IsValid() ? pilotPawn.WorldPosition : null;
	}

	Vector3 SampleGroundBelow( Vector3 from )
	{
		// Trace straight down, ignoring this drone hierarchy so we don't hit
		// our own body collider.
		var trace = Scene.Trace.Ray( from, from + Vector3.Down * MaxDropDistance )
			.IgnoreGameObjectHierarchy( GameObject )
			.Run();

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
