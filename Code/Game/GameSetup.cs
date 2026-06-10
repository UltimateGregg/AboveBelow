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
public sealed partial class GameSetup : Component, Component.INetworkListener
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

	void EnsureTeamComms()
	{
		var comms = Components.Get<TeamComms>();
		if ( !comms.IsValid() )
			comms = Components.Create<TeamComms>();

		comms.Setup = this;
	}

	bool ShouldSkipRuntimeScene()
	{
#if DEBUG
		if ( EditorRuntimePlaytestEnabled )
			return false;
#endif

		return Scene.IsEditor;
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
