namespace DroneVsPlayers;

/// <summary>
/// Drone variant chosen by a Pilot at round start. Determines flight feel,
/// jamming susceptibility, and whether a fiber-optic tether is rendered.
/// </summary>
public enum DroneType
{
	/// <summary>Long-range, GPS-guided. Fully susceptible to jamming.</summary>
	Gps = 0,
	/// <summary>Short-range, agile, video-link based. Susceptible to jamming.</summary>
	Fpv = 1,
	/// <summary>FPV with a physical fiber-optic tether. Immune to RF jamming.</summary>
	FiberOpticFpv = 2,
}
