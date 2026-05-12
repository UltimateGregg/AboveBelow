using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace DroneVsPlayers;

/// <summary>
/// Entry-point networking component. Drop this on a "GameManager" GameObject
/// in your main scene. It:
///   - creates a lobby if one isn't active (so single-player playtesting works)
///   - listens for connections and assigns each one to the smaller team
///     (Pilot team vs Soldier team)
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

	[Property] public bool RequireRoleChoice { get; set; } = true;
	[Property] public bool EnableSoloTrainingDummies { get; set; } = true;
	[Property, Range( 0, 8 )] public int SoloTrainingDummyCount { get; set; } = 3;
	[Property] public RoundManager Round { get; set; }
	[Property] public GameRules Rules { get; set; }

	/// <summary>Connection IDs assigned to the Pilot team.</summary>
	[Sync] public NetList<Guid> PilotTeam { get; set; } = new();

	/// <summary>Connection IDs assigned to the Soldier team.</summary>
	[Sync] public NetList<Guid> SoldierTeam { get; set; } = new();

	// Backwards-compat: original single-pilot field. The first connection on
	// PilotTeam mirrors here so legacy systems (PromotePilot, HudPanel) keep
	// working until they are migrated.
	[Sync] public Guid PilotConnectionId { get; set; }

	// Map connections -> spawned pawn (and pilot -> drone) for cleanup / role swaps.
	readonly Dictionary<Guid, GameObject> _pawns = new();
	readonly Dictionary<Guid, GameObject> _drones = new();
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

	readonly record struct TrainingDummySpawnPoint( Vector3 Position, Rotation Rotation, PlayerRole PreferredRole );

	protected override async Task OnLoad()
	{
		if ( Scene.IsEditor ) return;

		if ( !Networking.IsActive )
		{
			LoadingScreen.Title = "Creating Lobby";
			await Task.DelayRealtimeSeconds( 0.1f );
			Networking.CreateLobby( new() );
		}
	}

	protected override void OnStart()
	{
		if ( Scene.IsEditor ) return;
		CaptureTrainingDummySpawnPoints();
	}

	protected override void OnUpdate()
	{
		if ( Scene.IsEditor ) return;

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

	public void OnActive( Connection channel )
	{
		Log.Info( $"[GameSetup] {channel.DisplayName} joined." );

		if ( Networking.IsHost && Connection.All.Count > 1 )
			DespawnSoloTrainingDummies();

		var isLocalConnection = Connection.Local is not null && channel.Id == Connection.Local.Id;
		if ( RequireRoleChoice && isLocalConnection )
		{
			if ( _hasLocalLoadout )
			{
				SpawnSelectedLocalRole( channel );
				return;
			}

			Log.Info( "[GameSetup] Waiting for local class selection." );
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

	[Rpc.Broadcast]
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

		DespawnPawn( channel.Id );

		// Pilot's ground avatar.
		var groundPrefab = ResolvePilotGroundPrefab();
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

		DespawnPawn( channel.Id );

		var prefab = ResolveSoldierPrefab( cls );
		if ( !prefab.IsValid() )
		{
			Log.Warning( $"[GameSetup] Soldier prefab for {cls} not found." );
			return;
		}

		var spawn = PickSpawn( PlayerRole.Soldier );
		var pawn = prefab.Clone( spawn, name: $"{cls} - {channel.DisplayName}" );
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

		var prefab = ResolveTrainingDummyPrefab();
		if ( !prefab.IsValid() )
		{
			Log.Warning( "[GameSetup] Training dummy prefab not found." );
			return;
		}

		var spawns = PickTrainingDummySpawns( dummyRole, SoloTrainingDummyCount );
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

			var health = clone.Components.Get<Health>( FindMode.EverythingInSelfAndDescendants );
			if ( health.IsValid() && Rules.IsValid() )
				health.MaxHealth = dummyRole == PlayerRole.Pilot ? Rules.PilotGroundHealth : Rules.SoldierHealth;

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

	GameObject ResolvePilotGroundPrefab()
	{
		if ( PilotGroundPrefab.IsValid() ) return PilotGroundPrefab;
		if ( !string.IsNullOrWhiteSpace( PilotGroundPrefabPath ) )
		{
			var p = GameObject.GetPrefab( PilotGroundPrefabPath );
			if ( p.IsValid() ) return p;
		}
		// Fallback to the legacy soldier prefab so pilots at least spawn.
		return SoldierPrefab.IsValid() ? SoldierPrefab : GameObject.GetPrefab( SoldierPrefabPath );
	}

	GameObject ResolveTrainingDummyPrefab()
	{
		if ( TrainingDummyPrefab.IsValid() ) return TrainingDummyPrefab;
		if ( !string.IsNullOrWhiteSpace( TrainingDummyPrefabPath ) )
		{
			var p = GameObject.GetPrefab( TrainingDummyPrefabPath );
			if ( p.IsValid() ) return p;
		}
		return null;
	}

	GameObject ResolveSoldierPrefab( SoldierClass cls )
	{
		var (inspector, path) = cls switch
		{
			SoldierClass.Assault => (AssaultPrefab, AssaultPrefabPath),
			SoldierClass.CounterUav => (CounterUavPrefab, CounterUavPrefabPath),
			SoldierClass.Heavy => (HeavyPrefab, HeavyPrefabPath),
			_ => (SoldierPrefab, SoldierPrefabPath),
		};
		if ( inspector.IsValid() ) return inspector;
		if ( !string.IsNullOrWhiteSpace( path ) )
		{
			var p = GameObject.GetPrefab( path );
			if ( p.IsValid() ) return p;
		}
		return SoldierPrefab.IsValid() ? SoldierPrefab : GameObject.GetPrefab( SoldierPrefabPath );
	}

	GameObject ResolveDronePrefab( DroneType type )
	{
		var (inspector, path) = type switch
		{
			DroneType.Gps => (GpsDronePrefab, GpsDronePrefabPath),
			DroneType.Fpv => (FpvDronePrefab, FpvDronePrefabPath),
			DroneType.FiberOpticFpv => (FiberOpticFpvDronePrefab, FiberOpticFpvDronePrefabPath),
			_ => (DronePrefab, DronePrefabPath),
		};
		if ( inspector.IsValid() ) return inspector;
		if ( !string.IsNullOrWhiteSpace( path ) )
		{
			var p = GameObject.GetPrefab( path );
			if ( p.IsValid() ) return p;
		}
		return DronePrefab.IsValid() ? DronePrefab : GameObject.GetPrefab( DronePrefabPath );
	}

	public bool NeedsLocalRoleChoice()
	{
		if ( Scene.IsEditor ) return false;
		if ( !RequireRoleChoice ) return false;

		var hasLocalDrone = Scene.GetAllComponents<DroneController>().Any( d => !d.IsProxy );
		var hasLocalSoldier = Scene.GetAllComponents<GroundPlayerController>().Any( p => !p.IsProxy );
		return !hasLocalDrone && !hasLocalSoldier;
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
	// migrate. Promotes a pilot in the old single-pilot model. Now a no-op
	// against the team list — round rotation is driven by player choice.
	[Rpc.Broadcast]
	public void PromotePilot( Guid newPilotId )
	{
		if ( !Networking.IsHost ) return;
		PilotConnectionId = newPilotId;
	}

	// Legacy single-prefab spawn helper — preserved so RoundManager's role
	// rotation in ResetForNextRound keeps compiling. New code should call
	// SpawnPilotPawn / SpawnSoldierPawn directly.
	public void SpawnPawnFor( Connection channel, PlayerRole role )
	{
		if ( role == PlayerRole.Pilot )
			SpawnPilotPawn( channel, DroneType.Gps );
		else if ( role == PlayerRole.Soldier )
			SpawnSoldierPawn( channel, SoldierClass.Assault );
	}

	// Legacy: HudPanel calls this for the old "BELOW / ABOVE" picker. We
	// route both options into the new selection flow with a default class.
	public void SelectLocalRole( PlayerRole role )
	{
		if ( role == PlayerRole.Pilot )
			SelectLocalDrone( DroneType.Gps );
		else if ( role == PlayerRole.Soldier )
			SelectLocalSoldier( SoldierClass.Assault );
	}
}
