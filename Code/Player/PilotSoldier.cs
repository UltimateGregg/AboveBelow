using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Ground-side avatar for a drone pilot. Walks like a soldier but carries
/// no offensive weapon — the pilot's "weapon" is the RemoteController that
/// tethers them to a drone in the sky. Killable; when this dies, the
/// linked drone's PilotLink crashes the drone.
/// </summary>
[Title( "Pilot Soldier" )]
[Category( "Drone vs Players/Player" )]
[Icon( "settings_remote" )]
public sealed class PilotSoldier : Component
{
	/// <summary>The drone the pilot is currently flying.</summary>
	[Sync] public Guid LinkedDroneId { get; set; }

	/// <summary>Which type of drone the pilot picked at round start.</summary>
	[Sync] public DroneType ChosenDrone { get; set; }

	public DroneBase ResolveDrone()
	{
		if ( LinkedDroneId == default ) return null;
		return Scene.GetAllComponents<DroneBase>()
			.FirstOrDefault( d => d.GameObject.Id == LinkedDroneId );
	}
}
