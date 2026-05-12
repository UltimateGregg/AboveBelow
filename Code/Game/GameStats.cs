using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Networked player statistics tracker. Hosts maintain authoritative copy,
/// clients receive [Sync] updates. Scoreboard data for HUD display.
/// Reset each round.
/// </summary>
[Title( "Game Stats" )]
[Category( "Drone vs Players" )]
[Icon( "assessment" )]
public sealed class GameStats : Component
{
	/// <summary>Kill count per connection (player), replicated to all clients</summary>
	[Sync] public NetDictionary<Guid, int> PlayerKills { get; set; } = new();

	/// <summary>Death count per connection (player)</summary>
	[Sync] public NetDictionary<Guid, int> PlayerDeaths { get; set; } = new();

	/// <summary>Player names at round start (cached from Connection.DisplayName)</summary>
	[Sync] public NetDictionary<Guid, string> PlayerNames { get; set; } = new();

	/// <summary>Track who is the pilot this round (Guid of Connection)</summary>
	[Sync] public Guid PilotConnection { get; set; }

	protected override void OnAwake()
	{
		// Ensure valid dictionaries
		PlayerKills ??= new NetDictionary<Guid, int>();
		PlayerDeaths ??= new NetDictionary<Guid, int>();
		PlayerNames ??= new NetDictionary<Guid, string>();
	}

	/// <summary>Record a kill. Call from RoundManager when a player dies.</summary>
	public void RecordKill( Guid killerConnection, Guid killedConnection )
	{
		if ( !Networking.IsHost ) return;

		if ( !PlayerKills.ContainsKey( killerConnection ) )
			PlayerKills[killerConnection] = 0;

		PlayerKills[killerConnection]++;
	}

	/// <summary>Record a death. Call from RoundManager when a player dies.</summary>
	public void RecordDeath( Guid killedConnection )
	{
		if ( !Networking.IsHost ) return;

		if ( !PlayerDeaths.ContainsKey( killedConnection ) )
			PlayerDeaths[killedConnection] = 0;

		PlayerDeaths[killedConnection]++;
	}

	/// <summary>Cache player names at round start for display</summary>
	public void CachePlayerNames()
	{
		if ( !Networking.IsHost ) return;

		foreach ( var conn in Connection.All )
		{
			if ( !PlayerNames.ContainsKey( conn.Id ) )
				PlayerNames[conn.Id] = conn.DisplayName;
		}
	}

	/// <summary>Get combined kill/death ratio for sorting</summary>
	public int GetPlayerScore( Guid connectionId )
	{
		var kills = PlayerKills.ContainsKey( connectionId ) ? PlayerKills[connectionId] : 0;
		var deaths = PlayerDeaths.ContainsKey( connectionId ) ? PlayerDeaths[connectionId] : 1; // avoid div by zero

		return kills - deaths;
	}

	/// <summary>Get scoreboard sorted by score (descending)</summary>
	public List<(Guid ConnectionId, string Name, int Kills, int Deaths, int Score)> GetScoreboard()
	{
		var scores = new List<(Guid ConnectionId, string Name, int Kills, int Deaths, int Score)>();

		foreach ( var killEntry in PlayerKills )
		{
			var connId = killEntry.Key;
			var kills = killEntry.Value;
			var deaths = PlayerDeaths.ContainsKey( connId ) ? PlayerDeaths[connId] : 0;
			var name = PlayerNames.ContainsKey( connId ) ? PlayerNames[connId] : "Unknown";
			var score = GetPlayerScore( connId );

			scores.Add( (connId, name, kills, deaths, score) );
		}

		// Sort by score descending
		return scores.OrderByDescending( s => s.Score ).ToList();
	}

	/// <summary>Reset stats for next round</summary>
	public void ResetRound()
	{
		if ( !Networking.IsHost ) return;

		PlayerKills.Clear();
		PlayerDeaths.Clear();
		PlayerNames.Clear();
		PilotConnection = default;
	}
}
