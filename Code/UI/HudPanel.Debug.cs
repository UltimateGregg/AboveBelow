#if DEBUG
using Sandbox;
using Sandbox.UI;
using System;
using System.Linq;

namespace DroneVsPlayers;

public partial class HudPanel
{
	[ConCmd( "dvp_menu_click" )]
	public static void DebugMenuClick( string label = "PLAY" )
	{
		var hud = Game.ActiveScene?.GetAllComponents<HudPanel>().FirstOrDefault();
		if ( !hud.IsValid() )
		{
			Log.Warning( "[MenuClickProbe] HudPanel not found." );
			return;
		}

		if ( !hud.TryDebugMenuClick( label, out var note ) )
		{
			Log.Warning( $"[MenuClickProbe] Could not click '{label}'. {note}" );
			return;
		}

		Log.Info( $"[MenuClickProbe] {note}" );
	}

	bool TryDebugMenuClick( string label, out string note )
	{
		var normalized = NormalizeDebugClickLabel( label );
		var panelLabel = normalized switch
		{
			"play" => "PLAY",
			"soldiers" => "SOLDIERS",
			"soldier" => "SOLDIERS",
			"assault" => "ASSAULT",
			_ => ""
		};

		if ( string.IsNullOrWhiteSpace( panelLabel ) )
		{
			note = "Expected one of PLAY, SOLDIERS, or ASSAULT.";
			return false;
		}

		var clickedPanel = FindMenuPanelByText( panelLabel );
		if ( clickedPanel.IsValid() )
		{
			clickedPanel.CreateEvent( new MousePanelEvent( "onclick", clickedPanel, "mouseleft" ) );
			StateHasChanged();

			if ( DebugClickReachedState( normalized ) )
			{
				note = $"Dispatched live HUD onclick for {panelLabel}.";
				return true;
			}
		}

		if ( TryDebugMenuClickFallback( normalized, out note ) )
		{
			note = clickedPanel.IsValid()
				? $"Dispatched live HUD onclick for {panelLabel}; used deterministic fallback because the panel event did not settle immediately."
				: $"Used deterministic fallback for {panelLabel}; matching live panel text was not found.";
			return true;
		}

		return false;
	}

	Panel FindMenuPanelByText( string text )
	{
		if ( Panel is null )
			return null;

		return Panel.Descendants.FirstOrDefault( p =>
			string.Equals( (p.StringValue ?? "").Trim(), text, StringComparison.OrdinalIgnoreCase ) );
	}

	bool TryDebugMenuClickFallback( string normalized, out string note )
	{
		switch ( normalized )
		{
			case "play":
				StartFromMainMenu();
				note = "Clicked PLAY fallback through HudPanel.StartFromMainMenu.";
				return true;
			case "soldier":
			case "soldiers":
				SelectLoadoutTeam( PlayerRole.Soldier );
				note = "Clicked SOLDIERS fallback through HudPanel.SelectLoadoutTeam.";
				return true;
			case "assault":
				Setup?.SelectLocalSoldier( SoldierClass.Assault );
				note = "Clicked ASSAULT fallback through GameSetup.SelectLocalSoldier.";
				return true;
			default:
				note = "Unknown menu click label.";
				return false;
		}
	}

	bool DebugClickReachedState( string normalized )
	{
		return normalized switch
		{
			"play" => !ShowMainMenu,
			"soldier" or "soldiers" => SelectedLoadoutTeam == PlayerRole.Soldier,
			"assault" => !(Setup?.NeedsLocalRoleChoice() ?? true),
			_ => false
		};
	}

	static string NormalizeDebugClickLabel( string label )
	{
		return (label ?? "")
			.Trim()
			.Replace( "-", "", StringComparison.Ordinal )
			.Replace( "_", "", StringComparison.Ordinal )
			.Replace( " ", "", StringComparison.Ordinal )
			.ToLowerInvariant();
	}
}
#endif
