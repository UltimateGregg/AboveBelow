using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// First-person-view drone. Short range, agile, controlled over a video link
/// + RF telemetry. Susceptible to jamming, though slightly less than GPS
/// because brief signal dropouts don't immediately kill control authority.
/// </summary>
[Title( "FPV Drone" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "videocam" )]
public class FpvDrone : DroneBase
{
	public override DroneType Type => DroneType.Fpv;

	public override float JamSusceptibility { get; set; } = 0.85f;
}
