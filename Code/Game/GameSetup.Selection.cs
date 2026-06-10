using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace DroneVsPlayers;

// Team/loadout selection: connection join handling, team assignment, loadout definitions, HUD-driven role selection, round re-prompt flow.
public sealed partial class GameSetup
{
	public void OnActive( Connection channel )
	{
		Log.Info( $"[GameSetup] {channel.DisplayName} joined." );

		if ( Networking.IsHost && Connection.All.Count > 1 )
			DespawnSoloTrainingDummies();

		var isLocalConnection = Connection.Local is not null && channel.Id == Connection.Local.Id;
		if ( RequireRoleChoice )
		{
			if ( isLocalConnection && _hasLocalLoadout )
			{
				SpawnSelectedLocalRole( channel );
				return;
			}

			Log.Info( $"[GameSetup] Waiting for {channel.DisplayName} to choose a team and loadout." );
			return;
		}

		// Auto-fill smaller team for non-local connections (host's view of clients).
		var team = SmallerTeam();
		AssignConnectionToTeam( channel.Id, team );

		if ( team == PlayerRole.Pilot )
			SpawnPilotPawn( channel, DroneType.Gps );
		else
			SpawnSoldierPawn( channel, SoldierClass.Assault );
	}

	PlayerRole SmallerTeam()
	{
		var pilotCap = Rules.IsValid() ? Rules.PilotTeamSize : 3;
		var soldierCap = Rules.IsValid() ? Rules.SoldierTeamSize : 4;

		var pilotCount = PilotTeam.Count;
		var soldierCount = SoldierTeam.Count;

		// Respect caps: prefer the side with open seats.
		if ( pilotCount >= pilotCap ) return PlayerRole.Soldier;
		if ( soldierCount >= soldierCap ) return PlayerRole.Pilot;

		// Otherwise fill whichever is further from full.
		var pilotFill = pilotCap == 0 ? 1f : (float)pilotCount / pilotCap;
		var soldierFill = soldierCap == 0 ? 1f : (float)soldierCount / soldierCap;
		return pilotFill <= soldierFill ? PlayerRole.Pilot : PlayerRole.Soldier;
	}

	/// <summary>Host-only: stamp the team lists for a given connection.</summary>
	void AssignConnectionToTeam( Guid connId, PlayerRole role )
	{
		if ( !Networking.IsHost ) return;

		PilotTeam.Remove( connId );
		SoldierTeam.Remove( connId );

		if ( role == PlayerRole.Pilot )
		{
			PilotTeam.Add( connId );
			if ( PilotConnectionId == default )
				PilotConnectionId = connId;
		}
		else if ( role == PlayerRole.Soldier )
		{
			SoldierTeam.Add( connId );
			if ( PilotConnectionId == connId )
				PilotConnectionId = PilotTeam.FirstOrDefault();
		}
	}

	public PlayerRole GetConnectionRole( Guid connId )
	{
		if ( connId == default )
			return PlayerRole.Spectator;

		if ( PilotTeam.Contains( connId ) )
			return PlayerRole.Pilot;

		if ( SoldierTeam.Contains( connId ) )
			return PlayerRole.Soldier;

		return PlayerRole.Spectator;
	}

	public bool AreSameTeam( Guid a, Guid b )
	{
		if ( a == default || b == default )
			return false;

		var role = GetConnectionRole( a );
		return role is PlayerRole.Pilot or PlayerRole.Soldier && role == GetConnectionRole( b );
	}

	public LoadoutDefinitionResource GetSoldierLoadoutDefinition( SoldierClass cls )
	{
		return LoadoutCatalog.FindSoldier( EnumerateLoadoutDefinitions(), cls );
	}

	public LoadoutDefinitionResource GetDroneLoadoutDefinition( DroneType type )
	{
		return LoadoutCatalog.FindDrone( EnumerateLoadoutDefinitions(), type );
	}

	public LoadoutDefinitionResource GetAuthoredSoldierLoadoutDefinition( SoldierClass cls )
	{
		return EnumerateLoadoutDefinitions()
			.Where( d => d.IsSoldierDefinition && d.SoldierClass == cls )
			.LastOrDefault();
	}

	public LoadoutDefinitionResource GetAuthoredDroneLoadoutDefinition( DroneType type )
	{
		return EnumerateLoadoutDefinitions()
			.Where( d => d.IsDroneDefinition && d.DroneType == type )
			.LastOrDefault();
	}

	IEnumerable<LoadoutDefinitionResource> EnumerateLoadoutDefinitions()
	{
		if ( LoadoutDefinitions is not null )
		{
			foreach ( var definition in LoadoutDefinitions )
			{
				if ( definition is not null )
					yield return definition;
			}
		}

		foreach ( var definition in ResourceLibrary.GetAll<LoadoutDefinitionResource>() )
		{
			if ( definition is not null )
				yield return definition;
		}
	}

	// ── Local-player class selection (called from the HUD) ────────────────

	public void SelectLocalSoldier( SoldierClass cls )
	{
		_selectedLocalRole = PlayerRole.Soldier;
		_selectedLocalSoldier = cls;
		_hasLocalLoadout = true;

		var local = Connection.Local;
		if ( local is null )
		{
			Log.Warning( "[GameSetup] Local connection is not ready yet; selection is queued." );
			return;
		}

		RequestSpawn( local.Id, (int)PlayerRole.Soldier, (int)cls, (int)DroneType.Gps );
	}

	public void SelectLocalDrone( DroneType type )
	{
		_selectedLocalRole = PlayerRole.Pilot;
		_selectedLocalDrone = type;
		_hasLocalLoadout = true;

		var local = Connection.Local;
		if ( local is null )
		{
			Log.Warning( "[GameSetup] Local connection is not ready yet; selection is queued." );
			return;
		}

		RequestSpawn( local.Id, (int)PlayerRole.Pilot, (int)SoldierClass.Assault, (int)type );
	}

	[Rpc.Host]
	void RequestSpawn( Guid connId, int roleInt, int soldierClassInt, int droneTypeInt )
	{
		if ( !Networking.IsHost ) return;

		var role = (PlayerRole)roleInt;
		var cls = (SoldierClass)soldierClassInt;
		var type = (DroneType)droneTypeInt;

		var conn = Connection.All.FirstOrDefault( c => c.Id == connId );
		if ( conn is null )
		{
			Log.Warning( $"[GameSetup] RequestSpawn: connection {connId} not found." );
			return;
		}

		if ( role == PlayerRole.Pilot )
			_selectedDroneTypes[connId] = type;
		else if ( role == PlayerRole.Soldier )
			_selectedSoldierClasses[connId] = cls;

		AssignConnectionToTeam( connId, role );

		if ( role == PlayerRole.Pilot )
			SpawnPilotPawn( conn, type );
		else if ( role == PlayerRole.Soldier )
			SpawnSoldierPawn( conn, cls );

		RefreshSoloTrainingDummies( role );
	}

	void SpawnSelectedLocalRole( Connection local )
	{
		if ( !_hasLocalLoadout ) return;

		RequestSpawn( local.Id, (int)_selectedLocalRole,
			(int)_selectedLocalSoldier, (int)_selectedLocalDrone );
	}

	public void BeginNextRoundSelection()
	{
		if ( !Networking.IsHost ) return;

		foreach ( var connId in _pawns.Keys.Concat( _drones.Keys ).Distinct().ToList() )
		{
			DespawnPawn( connId );
		}

		DespawnSoloTrainingDummies();
		_selectedSoldierClasses.Clear();
		_selectedDroneTypes.Clear();
		PilotTeam.Clear();
		SoldierTeam.Clear();
		PilotConnectionId = default;
		SelectionGeneration++;

		ClearLocalLoadoutChoice( SelectionGeneration );
	}

	[Rpc.Broadcast]
	void ClearLocalLoadoutChoice( int generation )
	{
		LocalSelectionGeneration = Math.Max( LocalSelectionGeneration, generation );
		_selectedLocalRole = PlayerRole.Spectator;
		_selectedLocalSoldier = SoldierClass.Assault;
		_selectedLocalDrone = DroneType.Gps;
		_hasLocalLoadout = false;
		_timeSinceSpawnRetry = 0f;
	}

	public bool HasReadyPlayers( int minPlayers )
	{
		var connected = Connection.All.ToList();
		if ( connected.Count < minPlayers )
			return false;

		if ( !RequireRoleChoice )
			return true;

		return connected.All( c =>
			_pawns.TryGetValue( c.Id, out var pawn ) && pawn.IsValid() );
	}

	public bool NeedsLocalRoleChoice()
	{
		if ( ShouldSkipRuntimeScene() ) return false;
		if ( !RequireRoleChoice ) return false;

		var hasLocalDrone = Scene.GetAllComponents<DroneController>().Any( d => !d.IsProxy );
		var hasLocalSoldier = Scene.GetAllComponents<GroundPlayerController>().Any( p => !p.IsProxy );
		return !hasLocalDrone && !hasLocalSoldier;
	}

	// ── Legacy: kept so RoundManager + HUD continue to compile while we
	// migrate. It is not used by the next-round re-prompt flow.
	[Rpc.Broadcast]
	public void PromotePilot( Guid newPilotId )
	{
		if ( !Networking.IsHost ) return;

		var newPilot = Connection.All.FirstOrDefault( c => c.Id == newPilotId );
		if ( newPilot is null )
			return;

		var previousPilots = PilotTeam.ToList();
		foreach ( var pilotId in previousPilots )
		{
			if ( pilotId == newPilotId ) continue;

			var previousPilot = Connection.All.FirstOrDefault( c => c.Id == pilotId );
			if ( previousPilot is null ) continue;

			AssignConnectionToTeam( pilotId, PlayerRole.Soldier );
			SpawnSoldierPawn( previousPilot, GetSelectedSoldierClass( pilotId ) );
		}

		AssignConnectionToTeam( newPilotId, PlayerRole.Pilot );
		PilotConnectionId = newPilotId;
		SpawnPilotPawn( newPilot, GetSelectedDroneType( newPilotId ) );
	}

	SoldierClass GetSelectedSoldierClass( Guid connId )
	{
		return _selectedSoldierClasses.TryGetValue( connId, out var cls )
			? cls
			: SoldierClass.Assault;
	}

	DroneType GetSelectedDroneType( Guid connId )
	{
		return _selectedDroneTypes.TryGetValue( connId, out var type )
			? type
			: DroneType.Gps;
	}

	// Legacy: HudPanel calls this for the old direct role picker. We
	// route both options into the new selection flow with a default class.
	public void SelectLocalRole( PlayerRole role )
	{
		if ( role == PlayerRole.Pilot )
			SelectLocalDrone( DroneType.Gps );
		else if ( role == PlayerRole.Soldier )
			SelectLocalSoldier( SoldierClass.Assault );
	}
}
