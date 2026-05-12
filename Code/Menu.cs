using Sandbox;

namespace DroneVsPlayers;

[Title( "Menu" )]
[Category( "Drone vs Players/UI" )]
[Icon( "menu" )]
public sealed class Menu : Component
{
	protected override void OnStart()
	{
		EnsureMenuUi( GameObject );
	}

	internal static void EnsureMenuUi( GameObject gameObject )
	{
		if ( !gameObject.Components.Get<ScreenPanel>().IsValid() )
			gameObject.Components.Create<ScreenPanel>( true );

		if ( !gameObject.Components.Get<MainMenuPanel>().IsValid() )
			gameObject.Components.Create<MainMenuPanel>( true );
	}
}
