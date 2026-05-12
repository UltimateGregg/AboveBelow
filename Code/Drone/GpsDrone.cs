using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// GPS-guided long-range drone. Highly susceptible to jamming because its
/// position fix and command link both ride RF channels that a directional
/// jammer or chaff cloud can blanket.
/// </summary>
[Title( "GPS Drone" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "satellite_alt" )]
public sealed class GpsDrone : DroneBase
{
	public override DroneType Type => DroneType.Gps;

	public override float JamSusceptibility { get; set; } = 1f;
}
