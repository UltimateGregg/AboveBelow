using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace DroneVsPlayers;

/// <summary>
/// Entry-point networking component. Drop this on a "GameManager" GameObject
/// in your main scene. It:
///   - creates a lobby if one isn't active (so single-player playtesting works)
///   - listens for connections and waits for each client to choose a team
///     and loadout before spawning when role choice is enabled
///   - spawns the chosen prefab once a player picks a class / drone type
///   - for pilots, also spawns the chosen drone and links the two together
///
/// Class / drone-type selection comes from the HUD class-picker via
/// SelectSoldierClass / SelectDroneType, mirroring the original
/// SelectLocalRole flow.
/// </summary>
[Title( "Game Setup" )]
[Category( "Drone vs Players" )]
[Icon( "videogame_asset" )]
public sealed class GameSetup : Component, Component.INetworkListener
{
	// Prefab references (legacy single-prefab fields kept as fallbacks).
	[Property] public GameObject SoldierPrefab { get; set; }
	[Property] public GameObject DronePrefab { get; set; }
	[Property] public string SoldierPrefabPath { get; set; } = "prefabs/soldier.prefab";
	[Property] public string DronePrefabPath { get; set; } = "prefabs/drone.prefab";

	// Per-class soldier prefabs.
	[Property] public GameObject AssaultPrefab { get; set; }
	[Property] public GameObject CounterUavPrefab { get; set; }
	[Property] public GameObject HeavyPrefab { get; set; }
	[Property] public string AssaultPrefabPath { get; set; } = "prefabs/soldier_assault.prefab";
	[Property] public string CounterUavPrefabPath { get; set; } = "prefabs/soldier_counter_uav.prefab";
	[Property] public string HeavyPrefabPath { get; set; } = "prefabs/soldier_heavy.prefab";

	// Per-type drone prefabs + the pilot's ground avatar.
	[Property] public GameObject GpsDronePrefab { get; set; }
	[Property] public GameObject FpvDronePrefab { get; set; }
	[Property] public GameObject FiberOpticFpvDronePrefab { get; set; }
	[Property] public GameObject PilotGroundPrefab { get; set; }
	[Property] public GameObject TrainingDummyPrefab { get; set; }
	[Property] public string GpsDronePrefabPath { get; set; } = "prefabs/drone_gps.prefab";
	[Property] public string FpvDronePrefabPath { get; set; } = "prefabs/drone_fpv.prefab";
	[Property] public string FiberOpticFpvDronePrefabPath { get; set; } = "prefabs/drone_fpv_fiber.prefab";
	[Property] public string PilotGroundPrefabPath { get; set; } = "prefabs/pilot_ground.prefab";
	[Property] public string TrainingDummyPrefabPath { get; set; } = "prefabs/training_dummy.prefab";
	[Property] public List<LoadoutDefinitionResource> LoadoutDefinitions { get; set; } = new();

	[Property] public bool RequireRoleChoice { get; set; } = true;
	[Property] public bool JoinExistingEditorLobbyOnStart { get; set; } = true;
	[Property] public bool EnableSoloTrainingDummies { get; set; } = true;
	[Property, Range( 0, 8 )] public int SoloTrainingDummyCount { get; set; } = 3;
	[Property] public RoundManager Round { get; set; }
	[Property] public GameRules Rules { get; set; }

	/// <summary>Connection IDs assigned to the Pilot team.</summary>
	[Sync] public NetList<Guid> PilotTeam { get; set; } = new();

	/// <summary>Connection IDs assigned to the Soldier team.</summary>
	[Sync] public NetList<Guid> SoldierTeam { get; set; } = new();

	/// <summary>Increments each time the host reopens team/loadout selection.</summary>
	[Sync] public int SelectionGeneration { get; set; }

#if DEBUG
	[Property] public bool EditorRuntimePlaytestEnabled { get; set; }
	[Sync] public string EditorAutodriveMode { get; set; } = "";
	[Sync] public int EditorAutodriveToken { get; set; }
	public string EditorDebugSnapshot => RoundFlowDebugCommands.BuildSnapshot( "component", this );
#endif

	public int LocalSelectionGeneration { get; private set; }

	// Backwards-compat: original single-pilot field. The first connection on
	// PilotTeam mirrors here so legacy systems (PromotePilot, HudPanel) keep
	// working until they are migrated.
	[Sync] public Guid PilotConnectionId { get; set; }

	// Map connections -> spawned pawn (and pilot -> drone) for cleanup / role swaps.
	readonly Dictionary<Guid, GameObject> _pawns = new();
	readonly Dictionary<Guid, GameObject> _drones = new();
	readonly Dictionary<Guid, SoldierClass> _selectedSoldierClasses = new();
	readonly Dictionary<Guid, DroneType> _selectedDroneTypes = new();
	readonly List<GameObject> _soloTrainingDummies = new();
	readonly List<TrainingDummySpawnPoint> _trainingDummySpawnPoints = new();

	PlayerRole _selectedLocalRole = PlayerRole.Spectator;
	SoldierClass _selectedLocalSoldier = SoldierClass.Assault;
	DroneType _selectedLocalDrone = DroneType.Gps;
	bool _hasLocalLoadout;
	bool _trainingDummySpawnPointsCaptured;
	PlayerRole _soloTrainingDummyRole = PlayerRole.Spectator;
	TimeSince _timeSinceSpawnRetry = 10f;
	TimeSince _timeSinceTrainingDummyCheck = 10f;
	bool _editorLobbyDataStamped;
	bool _networkStartupStarted;

	readonly record struct TrainingDummySpawnPoint( Vector3 Position, Rotation Rotation, PlayerRole PreferredRole );

	protected override async Task OnLoad()
	{
		if ( ShouldSkipRuntimeScene() ) return;

		await EnsureNetworkingActive();
	}

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

	protected override void OnStart()
	{
		if ( ShouldSkipRuntimeScene() ) return;
		ResolveManagerRefs();
		if ( Rules.IsValid() )
			Rules.ApplyBalanceConfig();
		EnsureTeamComms();
		CaptureTrainingDummySpawnPoints();
	}

	protected override void OnUpdate()
	{
		if ( ShouldSkipRuntimeScene() ) return;
		if ( !Networking.IsActive )
			_ = EnsureNetworkingActive();

		ResolveManagerRefs();
		TryStampEditorLobbyData();

#if DEBUG
		RoundFlowDebugCommands.TickEditorAutodrive( this );
#endif

		if ( Networking.IsHost && _timeSinceTrainingDummyCheck > 1f )
		{
			_timeSinceTrainingDummyCheck = 0f;
			if ( Connection.All.Count > 1 )
				DespawnSoloTrainingDummies();
		}

		if ( !_hasLocalLoadout ) return;
		if ( !NeedsLocalRoleChoice() ) return;
		if ( _timeSinceSpawnRetry < 0.25f ) return;

		_timeSinceSpawnRetry = 0f;

		var local = Connection.Local;
		if ( local is null ) return;

		SpawnSelectedLocalRole( local );
	}

	protected override void OnDestroy()
	{
		if ( Game.IsEditor && Networking.IsActive )
			Networking.Disconnect();
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

	// ── Spawning ──────────────────────────────────────────────────────────

	void SpawnPilotPawn( Connection channel, DroneType type )
	{
		if ( !CanHostSpawn( channel ) ) return;

		_selectedDroneTypes[channel.Id] = type;
		DespawnPawn( channel.Id );

		// Pilot's ground avatar.
		var groundPrefab = GameSetupPrefabResolver.ResolvePilotGroundPrefab( this );
		if ( !groundPrefab.IsValid() )
		{
			Log.Warning( "[GameSetup] Pilot ground prefab not found." );
			return;
		}

		var spawn = PickSpawn( PlayerRole.Pilot );
		var pawn = groundPrefab.Clone( spawn, name: $"Pilot - {channel.DisplayName}" );
		var pilot = pawn.Components.Get<PilotSoldier>( FindMode.EverythingInSelfAndDescendants );
		if ( pilot.IsValid() )
			pilot.ChosenDrone = type;
		BalanceApplier.ApplyPilotGround( pawn, GetActiveBalanceConfig() );
		EnsureTeamVoice( pawn );

		if ( Networking.IsActive )
			pawn.NetworkSpawn( channel );
		_pawns[channel.Id] = pawn;

		// Drone is no longer auto-spawned here. The pilot starts holding the
		// drone in slot 1 (see DroneDeployer on the pilot prefab) and launches
		// it manually with LMB. PilotSoldier.LinkedDroneId is written by
		// DroneDeployer.ServerLaunchDrone when a launch happens.
	}

	void SpawnSoldierPawn( Connection channel, SoldierClass cls )
	{
		if ( !CanHostSpawn( channel ) ) return;

		_selectedSoldierClasses[channel.Id] = cls;
		DespawnPawn( channel.Id );

		var prefab = GameSetupPrefabResolver.ResolveSoldierPrefab( this, cls );
		if ( !prefab.IsValid() )
		{
			Log.Warning( $"[GameSetup] Soldier prefab for {cls} not found." );
			return;
		}

		var spawn = PickSpawn( PlayerRole.Soldier );
		var pawn = prefab.Clone( spawn, name: $"{cls} - {channel.DisplayName}" );
		BalanceApplier.ApplySoldier( pawn, cls, GetActiveBalanceConfig() );
		EnsureTeamVoice( pawn );
		if ( Networking.IsActive )
			pawn.NetworkSpawn( channel );
		_pawns[channel.Id] = pawn;
	}

	void DespawnPawn( Guid connId )
	{
		if ( _pawns.TryGetValue( connId, out var existing ) && existing.IsValid() )
			existing.Destroy();
		_pawns.Remove( connId );

		if ( _drones.TryGetValue( connId, out var existingDrone ) && existingDrone.IsValid() )
			existingDrone.Destroy();
		_drones.Remove( connId );
	}

	void RefreshSoloTrainingDummies( PlayerRole selectedRole )
	{
		if ( !Networking.IsHost ) return;

		CaptureTrainingDummySpawnPoints();

		var dummyRole = OpposingRole( selectedRole );
		var shouldSpawn = EnableSoloTrainingDummies
			&& SoloTrainingDummyCount > 0
			&& dummyRole != PlayerRole.Spectator
			&& Connection.All.Count <= 1;

		if ( !shouldSpawn )
		{
			DespawnSoloTrainingDummies();
			return;
		}

		_soloTrainingDummies.RemoveAll( d => !d.IsValid() );
		if ( _soloTrainingDummyRole == dummyRole && _soloTrainingDummies.Count == SoloTrainingDummyCount )
			return;

		DespawnSoloTrainingDummies();

		var prefab = GameSetupPrefabResolver.ResolveTrainingDummyPrefab( this );
		if ( !prefab.IsValid() )
		{
			Log.Warning( "[GameSetup] Training dummy prefab not found." );
			return;
		}
		// Place solo targets near the selected player side; their team role still stays opposing.
		var spawns = PickTrainingDummySpawns( selectedRole, SoloTrainingDummyCount );
		for ( var i = 0; i < spawns.Count; i++ )
		{
			var spawn = spawns[i];
			var clone = prefab.Clone( new Transform( spawn.Position, spawn.Rotation ), name: $"Training Dummy ({dummyRole}) {i + 1}" );

			var dummy = clone.Components.Get<TrainingDummy>( FindMode.EverythingInSelfAndDescendants );
			if ( dummy.IsValid() )
			{
				dummy.TeamRole = dummyRole;
				dummy.MoveAround = true;
				dummy.SetHomePosition( spawn.Position );
			}

			BalanceApplier.ApplyTrainingDummy( clone, dummyRole, GetActiveBalanceConfig() );

			if ( Networking.IsActive )
				clone.NetworkSpawn();

			_soloTrainingDummies.Add( clone );
		}

		_soloTrainingDummyRole = dummyRole;
	}

	void DespawnSoloTrainingDummies()
	{
		foreach ( var dummy in _soloTrainingDummies )
		{
			if ( dummy.IsValid() )
				dummy.Destroy();
		}

		_soloTrainingDummies.Clear();
		_soloTrainingDummyRole = PlayerRole.Spectator;
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

	bool CanHostSpawn( Connection channel )
	{
		if ( channel is null )
		{
			Log.Warning( "[GameSetup] Cannot spawn pawn; connection is not ready." );
			return false;
		}
		if ( Networking.IsActive && !Networking.IsHost )
		{
			Log.Warning( "[GameSetup] Cannot spawn pawn on a non-host client yet." );
			return false;
		}
		return true;
	}

	void EnsureTeamComms()
	{
		var comms = Components.Get<TeamComms>();
		if ( !comms.IsValid() )
			comms = Components.Create<TeamComms>();

		comms.Setup = this;
	}

	void EnsureTeamVoice( GameObject pawn )
	{
		if ( !pawn.IsValid() )
			return;

		var voice = pawn.Components.Get<TeamVoice>( FindMode.EverythingInSelfAndDescendants );
		if ( !voice.IsValid() )
			voice = pawn.Components.Create<TeamVoice>();

		voice.Setup = this;
		voice.ApplyVoiceRoutingProfile();
	}

	public bool NeedsLocalRoleChoice()
	{
		if ( ShouldSkipRuntimeScene() ) return false;
		if ( !RequireRoleChoice ) return false;

		var hasLocalDrone = Scene.GetAllComponents<DroneController>().Any( d => !d.IsProxy );
		var hasLocalSoldier = Scene.GetAllComponents<GroundPlayerController>().Any( p => !p.IsProxy );
		return !hasLocalDrone && !hasLocalSoldier;
	}

	bool ShouldSkipRuntimeScene()
	{
#if DEBUG
		if ( EditorRuntimePlaytestEnabled )
			return false;
#endif

		return Scene.IsEditor;
	}

	Transform PickSpawn( PlayerRole role )
	{
		var spawns = Scene.GetAllComponents<PlayerSpawn>()
			.Where( s => IsSpawnForRole( s, role ) )
			.OrderByDescending( s => s.Priority )
			.ToList();

		if ( spawns.Count == 0 )
			return new Transform( Vector3.Up * 64f );

		var topPriority = spawns[0].Priority;
		var top = spawns.Where( s => s.Priority == topPriority ).ToList();
		return Random.Shared.FromList( top, default ).WorldTransform;
	}

	void CaptureTrainingDummySpawnPoints()
	{
		if ( _trainingDummySpawnPointsCaptured ) return;
		_trainingDummySpawnPointsCaptured = true;

		foreach ( var marker in Scene.GetAllComponents<TrainingDummySpawn>() )
		{
			if ( !marker.IsValid() ) continue;
			_trainingDummySpawnPoints.Add( new TrainingDummySpawnPoint( marker.WorldPosition, marker.WorldRotation, marker.PreferredRole ) );
		}

		var legacyMarkers = Scene.GetAllComponents<TrainingDummy>()
			.Select( d => d.GameObject )
			.Distinct()
			.ToList();

		foreach ( var marker in legacyMarkers )
		{
			if ( !marker.IsValid() ) continue;
			_trainingDummySpawnPoints.Add( new TrainingDummySpawnPoint( marker.WorldPosition, marker.WorldRotation, PlayerRole.Spectator ) );
			marker.Destroy();
		}

		if ( _trainingDummySpawnPoints.Count > 0 )
			Log.Info( $"[GameSetup] Converted {_trainingDummySpawnPoints.Count} placed training dummies into runtime spawn points." );
	}

	List<TrainingDummySpawnPoint> PickTrainingDummySpawns( PlayerRole role, int count )
	{
		var source = _trainingDummySpawnPoints.Count > 0
			? _trainingDummySpawnPoints
			: Scene.GetAllComponents<PlayerSpawn>()
				.Where( s => IsSpawnForRole( s, role ) )
				.Select( s => new TrainingDummySpawnPoint( s.WorldPosition, s.WorldRotation, s.Role ) )
				.ToList();

		if ( source.Count == 0 )
			source = new List<TrainingDummySpawnPoint> { new( Vector3.Up * 64f, Rotation.Identity, PlayerRole.Spectator ) };

		var explicitPreferred = source.Where( s => s.PreferredRole == role ).ToList();
		var sidePreferred = role == PlayerRole.Pilot
			? source.Where( s => s.PreferredRole == PlayerRole.Spectator && s.Position.x >= 0f ).OrderByDescending( s => s.Position.x ).ToList()
			: source.Where( s => s.PreferredRole == PlayerRole.Spectator && s.Position.x <= 0f ).OrderBy( s => s.Position.x ).ToList();

		var preferred = explicitPreferred.Concat( sidePreferred ).ToList();

		var ordered = preferred
			.Concat( source.Where( s => !preferred.Contains( s ) ).OrderBy( s => MathF.Abs( s.Position.x ) ) )
			.ToList();

		var result = new List<TrainingDummySpawnPoint>();
		for ( var i = 0; i < count; i++ )
		{
			var spawn = ordered[i % ordered.Count];
			if ( i >= ordered.Count )
			{
				var angle = i * MathF.PI * 0.65f;
				spawn = spawn with
				{
					Position = spawn.Position + new Vector3( MathF.Cos( angle ) * 96f, MathF.Sin( angle ) * 96f, 0f )
				};
			}
			result.Add( spawn );
		}

		return result;
	}

	static bool IsSpawnForRole( PlayerSpawn spawn, PlayerRole role )
	{
		if ( spawn.Role == role ) return true;

		return role switch
		{
			PlayerRole.Pilot => spawn.GameObject.Tags.Has( "DroneSpawn" ),
			PlayerRole.Soldier => spawn.GameObject.Tags.Has( "PlayerSpawn" ),
			_ => false,
		};
	}

	static PlayerRole OpposingRole( PlayerRole role )
	{
		return role switch
		{
			PlayerRole.Pilot => PlayerRole.Soldier,
			PlayerRole.Soldier => PlayerRole.Pilot,
			_ => PlayerRole.Spectator,
		};
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

	// Role-only respawn helper for round rotation and legacy callers.
	public void RespawnWithSelectedLoadout( Connection channel, PlayerRole role )
	{
		if ( channel is null ) return;

		if ( role == PlayerRole.Pilot )
			SpawnPilotPawn( channel, GetSelectedDroneType( channel.Id ) );
		else if ( role == PlayerRole.Soldier )
			SpawnSoldierPawn( channel, GetSelectedSoldierClass( channel.Id ) );
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

	public void SpawnPawnFor( Connection channel, PlayerRole role )
	{
		RespawnWithSelectedLoadout( channel, role );
	}

#if DEBUG
	public void DebugSpawnPilotPawnForProbe( Connection channel, DroneType type )
	{
		if ( channel is null )
			return;

		RequireRoleChoice = false;
		_selectedLocalRole = PlayerRole.Pilot;
		_selectedLocalDrone = type;
		_hasLocalLoadout = true;
		_selectedDroneTypes[channel.Id] = type;

		AssignConnectionToTeam( channel.Id, PlayerRole.Pilot );
		SpawnPilotPawn( channel, type );
		RefreshSoloTrainingDummies( PlayerRole.Pilot );
	}
#endif

	// Legacy: HudPanel calls this for the old direct role picker. We
	// route both options into the new selection flow with a default class.
	public void SelectLocalRole( PlayerRole role )
	{
		if ( role == PlayerRole.Pilot )
			SelectLocalDrone( DroneType.Gps );
		else if ( role == PlayerRole.Soldier )
			SelectLocalSoldier( SoldierClass.Assault );
	}

	void ResolveManagerRefs()
	{
		if ( !Rules.IsValid() )
			Rules = Components.Get<GameRules>() ?? Scene.GetAllComponents<GameRules>().FirstOrDefault();

		if ( !Round.IsValid() )
			Round = Components.Get<RoundManager>() ?? Scene.GetAllComponents<RoundManager>().FirstOrDefault();
	}

	BalanceConfigResource GetActiveBalanceConfig()
	{
		if ( !Rules.IsValid() )
			ResolveManagerRefs();

		return Rules.IsValid() ? Rules.GetActiveBalanceConfig() : null;
	}
}
