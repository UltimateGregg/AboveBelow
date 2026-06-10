using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace DroneVsPlayers;

// Lobby startup: creates or joins the local editor lobby and stamps its discovery data.
public sealed partial class GameSetup
{
	async Task EnsureNetworkingActive()
	{
		if ( Networking.IsActive ) return;
		if ( _networkStartupStarted ) return;

		_networkStartupStarted = true;

		if ( Game.IsEditor && JoinExistingEditorLobbyOnStart && await TryJoinExistingEditorLobby() )
			return;

		LoadingScreen.Title = "Creating Lobby";
		await Task.DelayRealtimeSeconds( 0.1f );
		Networking.CreateLobby( new()
		{
			Name = "ABOVE / BELOW Local Editor",
			MaxPlayers = 8,
		} );
	}

	async Task<bool> TryJoinExistingEditorLobby()
	{
		var projectIdent = Project.Current?.Config?.FullIdent;
		if ( string.IsNullOrWhiteSpace( projectIdent ) )
			return false;

		LoadingScreen.Title = "Joining Local Lobby";
		await Task.DelayRealtimeSeconds( 0.35f );

		if ( Networking.IsActive )
			return true;

		try
		{
			var joined = await Networking.JoinBestLobby( projectIdent );
			if ( joined )
			{
				Log.Info( $"[GameSetup] Joined existing editor lobby for {projectIdent}." );
				return true;
			}

			if ( await TryJoinQueriedEditorLobby( projectIdent ) )
				return true;
		}
		catch ( Exception ex )
		{
			Log.Warning( $"[GameSetup] Could not join existing editor lobby: {ex.Message}" );
		}

		Log.Info( $"[GameSetup] No existing editor lobby found for {projectIdent}; creating one." );
		return false;
	}

	async Task<bool> TryJoinQueriedEditorLobby( string projectIdent )
	{
		var filters = new Dictionary<string, string>
		{
			{ "game", projectIdent },
		};
		var lobbies = await Networking.QueryLobbies( filters, includeServers: false, CancellationToken.None );
		var lobby = lobbies
			.Where( l => !l.IsFull )
			.FirstOrDefault( l =>
				l.Get( "dvp_local_editor", "" ) == "1"
				|| l.Get( "dvp_project_ident", "" ) == projectIdent
				|| l.Name == "ABOVE / BELOW Local Editor" );

		Log.Info( $"[GameSetup] Queried {lobbies.Count} editor lobby candidate(s) for {projectIdent}." );
		if ( lobby.LobbyId == 0 )
			return false;

		Log.Info( $"[GameSetup] Connecting to editor lobby '{lobby.Name}' lobby={lobby.LobbyId} owner={lobby.OwnerId} members={lobby.Members}/{lobby.MaxMembers}." );
		if ( await Networking.TryConnectSteamId( lobby.LobbyId ) )
		{
			Log.Info( $"[GameSetup] Connected to editor lobby '{lobby.Name}'." );
			return true;
		}

		return false;
	}

	void TryStampEditorLobbyData()
	{
		if ( _editorLobbyDataStamped ) return;
		if ( !Game.IsEditor || !Networking.IsHost ) return;

		var projectIdent = Project.Current?.Config?.FullIdent ?? "unknown";
		Networking.SetData( "dvp_local_editor", "1" );
		Networking.SetData( "dvp_project_ident", projectIdent );
		_editorLobbyDataStamped = true;
	}
}
