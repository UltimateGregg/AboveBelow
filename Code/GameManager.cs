using Sandbox;

namespace DroneVsPlayers;

[Title( "Game Manager" )]
[Category( "Drone vs Players" )]
[Icon( "videogame_asset" )]
public sealed class GameManager : Component
{
	protected override void OnStart()
	{
		Log.Info( "[GameManager] Started." );
	}
}
