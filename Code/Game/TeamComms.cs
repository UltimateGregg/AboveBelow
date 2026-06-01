using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Built-in chat filter for team-scoped text commands. Normal chat remains
/// global; /team and /t are filtered to the sender's current team.
/// </summary>
[Title( "Team Comms" )]
[Category( "Drone vs Players/Game" )]
[Icon( "forum" )]
public sealed class TeamComms : Component, IChatEvent
{
	[Property] public GameSetup Setup { get; set; }
	[Property] public bool EnableTeamChat { get; set; } = true;
	[Property] public string TeamPrefix { get; set; } = "[TEAM]";

	protected override void OnStart()
	{
		ResolveSetup();
	}

	public void OnChatMessage( ChatMessageEvent e )
	{
		if ( !EnableTeamChat || e is null || e.Sender is null || string.IsNullOrWhiteSpace( e.Message ) )
			return;

		ResolveSetup();
		if ( !Setup.IsValid() )
			return;

		if ( !TryStripTeamCommand( e.Message, out var body ) )
			return;

		e.Suppress = true;

		if ( string.IsNullOrWhiteSpace( body ) )
		{
			AddLocalFeedback( e.Sender, "Usage: /team <message>" );
			return;
		}

		var senderRole = Setup.GetConnectionRole( e.Sender.Id );
		if ( senderRole is not (PlayerRole.Pilot or PlayerRole.Soldier) )
		{
			AddLocalFeedback( e.Sender, "Join a team before using team chat." );
			return;
		}

		e.Suppress = false;
		e.Message = $"{TeamPrefix} {body.Trim()}";
		e.RecipientFilter = recipient => recipient is not null && Setup.AreSameTeam( e.Sender.Id, recipient.Id );
	}

	void ResolveSetup()
	{
		if ( Setup.IsValid() )
			return;

		Setup = Components.Get<GameSetup>() ?? Scene.GetAllComponents<GameSetup>().FirstOrDefault();
	}

	static bool TryStripTeamCommand( string message, out string body )
	{
		body = "";
		var trimmed = message.Trim();
		if ( trimmed.StartsWith( "/team ", StringComparison.OrdinalIgnoreCase ) )
		{
			body = trimmed[6..];
			return true;
		}

		if ( trimmed.StartsWith( "/t ", StringComparison.OrdinalIgnoreCase ) )
		{
			body = trimmed[3..];
			return true;
		}

		return false;
	}

	static void AddLocalFeedback( Connection sender, string message )
	{
		if ( sender is null || Connection.Local is null || sender.Id != Connection.Local.Id )
			return;

		Sandbox.Platform.Chat.AddText( message );
	}
}
