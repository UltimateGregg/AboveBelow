using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// FPV drone whose control link runs over a physical fiber-optic tether back
/// to the pilot. Immune to RF jamming — the cable carries video and inputs
/// regardless of any drone gun, chaff, or EMP nearby. Counter is to shoot
/// the drone or kill the pilot.
/// </summary>
[Title( "Fiber-Optic FPV Drone" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "cable" )]
public sealed class FiberOpticFpvDrone : FpvDrone
{
	public override DroneType Type => DroneType.FiberOpticFpv;

	public override float JamSusceptibility { get; set; } = 0f;
}
