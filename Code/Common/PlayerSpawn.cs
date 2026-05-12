using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Marker component placed on GameObjects in the scene to indicate spawn
/// locations. Drop one or more of each type around the map.
/// </summary>
[Title( "Player Spawn" )]
[Category( "Drone vs Players" )]
[Icon( "place" )]
public sealed class PlayerSpawn : Component
{
	[Property] public PlayerRole Role { get; set; } = PlayerRole.Soldier;

	/// <summary>
	/// Higher priority spawns are picked first when multiple are valid.
	/// Useful for round-start spawns vs. mid-round respawns.
	/// </summary>
	[Property] public int Priority { get; set; } = 0;

	protected override void DrawGizmos()
	{
		// Visual marker in the editor so you can see spawns at a glance.
		var color = Role switch
		{
			PlayerRole.Pilot => Color.Cyan,
			PlayerRole.Soldier => Color.Green,
			_ => Color.Yellow,
		};

		Gizmo.Draw.Color = color;
		Gizmo.Draw.LineSphere( new Sphere( 0, 16f ) );
		Gizmo.Draw.Arrow( Vector3.Zero, Vector3.Forward * 48f, 8f, 4f );
	}
}
