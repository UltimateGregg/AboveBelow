using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Identity component for any drone variant. The shared flight model lives
/// on DroneController; this component carries only the type-specific data
/// (jamming susceptibility, telemetry/recon flags) plus a hook for variant
/// behavior. Concrete variants: GpsDrone, FpvDrone, FiberOpticFpvDrone.
/// </summary>
[Title( "Drone Base" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "category" )]
public abstract class DroneBase : Component
{
	/// <summary>
	/// What kind of drone this is. Used by HUD, scoring, and equipment that
	/// wants to filter by type (e.g. recon-only loadouts).
	/// </summary>
	public abstract DroneType Type { get; }

	/// <summary>
	/// Multiplier on incoming jam strength. 1.0 = fully susceptible,
	/// 0.0 = immune (e.g. fiber-optic FPV — its control runs over a cable).
	/// </summary>
	[Property, Range( 0f, 1f )] public virtual float JamSusceptibility { get; set; } = 1f;

	/// <summary>True once a crash sequence has been triggered (pilot KIA, etc).</summary>
	[Sync] public bool IsCrashing { get; set; }
}
