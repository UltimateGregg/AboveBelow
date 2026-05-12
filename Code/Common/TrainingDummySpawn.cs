using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Marker for runtime training dummy spawn positions. The marker itself is
/// never a target; GameSetup uses it to spawn solo practice dummies only when
/// the local player has selected a team and no other real players are present.
/// </summary>
[Title( "Training Dummy Spawn" )]
[Category( "Drone vs Players" )]
[Icon( "accessibility_new" )]
public sealed class TrainingDummySpawn : Component
{
	[Property] public PlayerRole PreferredRole { get; set; } = PlayerRole.Spectator;

	protected override void DrawGizmos()
	{
		var color = PreferredRole switch
		{
			PlayerRole.Pilot => Color.Cyan,
			PlayerRole.Soldier => Color.Orange,
			_ => Color.Yellow,
		};

		Gizmo.Draw.Color = color;
		Gizmo.Draw.LineSphere( new Sphere( 0f, 18f ) );
		Gizmo.Draw.Arrow( Vector3.Zero, Vector3.Forward * 40f, 8f, 4f );
	}
}
