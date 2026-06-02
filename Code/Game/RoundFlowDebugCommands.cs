#if DEBUG
using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// DEBUG-only helpers for local two-editor round-flow proof. These commands use
/// the same public selection and damage paths as the UI/gameplay, then log
/// compact probes for external agent checks.
/// </summary>
public static class RoundFlowDebugCommands
{
	static int _lastAutodriveToken = -1;
	static int _lastAutodriveSelectionGeneration = -1;
	static int _autodriveEliminations;
	static TimeSince _timeSinceAutodrivePoll = 10f;

	[ConCmd( "dvp_round_probe" )]
	public static void Probe( string label = "manual" )
	{
		LogProbe( label );
	}

	[ConCmd( "dvp_pilot_deployer_visual_probe" )]
	public static void PilotDeployerVisualProbe( string droneType = "Fpv" )
	{
		if ( !Enum.TryParse<DroneType>( droneType, true, out var selectedType ) )
		{
			Log.Warning( $"[RoundProbe] Unknown DroneType '{droneType}'." );
			LogProbe( $"pilot-deployer-visual-unknown-{droneType}" );
			return;
		}

		if ( Networking.IsActive && !Networking.IsHost )
		{
			Log.Warning( "[RoundProbe] dvp_pilot_deployer_visual_probe must run on the host." );
			LogProbe( "pilot-deployer-visual-not-host" );
			return;
		}

		var scene = Game.ActiveScene;
		var setup = Find<GameSetup>();
		var local = Connection.Local ?? Connection.All.FirstOrDefault();
		if ( scene is null || local is null )
		{
			Log.Warning( "[RoundProbe] Cannot run pilot deployer visual probe without an active scene and local connection." );
			LogProbe( "pilot-deployer-visual-no-local" );
			return;
		}

		if ( setup is not null && setup.IsValid() )
		{
			setup.DebugSpawnPilotPawnForProbe( local, selectedType );
		}

		var pilot = scene.GetAllComponents<PilotSoldier>()
			.FirstOrDefault( p => !p.IsProxy && p.GameObject.Network.Owner?.Id == local.Id )
			?? scene.GetAllComponents<PilotSoldier>().FirstOrDefault( p => !p.IsProxy );

		if ( !pilot.IsValid() )
		{
			Log.Warning( "[RoundProbe] Pilot deployer visual probe could not find a local pilot pawn." );
			LogProbe( "pilot-deployer-visual-no-pilot" );
			return;
		}

		DestroyExtraLocalPilotPawns( scene, pilot, local.Id );
		LocalOptionsState.SetOpen( false );

		pilot.ChosenDrone = selectedType;
		pilot.LinkedDroneId = default;

		foreach ( var linkedDrone in scene.GetAllComponents<DroneBase>()
			.Where( drone => IsProbeDroneLinkedTo( drone, pilot, local.Id ) )
			.ToList() )
		{
			linkedDrone.GameObject.Destroy();
		}

		var remote = pilot.Components.Get<RemoteController>( FindMode.EverythingInSelfAndDescendants );
		if ( remote.IsValid() )
		{
			remote.DroneViewActive = false;
			remote.SetDroneViewActive( false );
		}

		var loadout = pilot.Components.Get<SoldierLoadout>( FindMode.EverythingInSelfAndDescendants );
		if ( loadout.IsValid() )
			loadout.SelectSlot( SoldierLoadout.PrimarySlot );

		var controller = pilot.Components.Get<GroundPlayerController>( FindMode.EverythingInSelfAndDescendants );
		if ( controller.IsValid() )
			controller.FirstPerson = true;

		var deployer = pilot.Components.Get<DroneDeployer>( FindMode.EverythingInSelfAndDescendants );
		if ( deployer.IsValid() )
		{
			deployer.DroneInFlight = false;
			deployer.LaunchReadyAt = 0f;
			deployer.ApplySelectionVisualState();
			Log.Info( $"[RoundProbe] Pilot deployer uses stock S&Box body hands for first-person IK: bodyHands={deployer.UsePilotBodyHands}, holdType={deployer.PilotHandHoldType}." );
		}

		Log.Info( $"[RoundProbe] Pilot deployer visual proof active: local pilot is holding the {selectedType} drone under the right hand and RC controller at the left hand." );
		LogProbe( $"pilot-deployer-visual-active-{selectedType}" );
	}

	[ConCmd( "dvp_fpv_visual_probe" )]
	public static void FpvVisualProbe( string droneType = "Fpv", string view = "FirstPerson" )
	{
		if ( !Enum.TryParse<DroneType>( droneType, true, out var selectedType ) )
		{
			Log.Warning( $"[RoundProbe] Unknown DroneType '{droneType}'." );
			LogProbe( $"fpv-visual-unknown-{droneType}" );
			return;
		}

		if ( !Networking.IsHost )
		{
			Log.Warning( "[RoundProbe] dvp_fpv_visual_probe must run on the host." );
			LogProbe( "fpv-visual-not-host" );
			return;
		}

		var scene = Game.ActiveScene;
		var setup = Find<GameSetup>();
		var local = Connection.Local ?? Connection.All.FirstOrDefault();
		if ( scene is null || local is null )
		{
			Log.Warning( "[RoundProbe] Cannot run FPV visual probe without an active scene and local connection." );
			LogProbe( "fpv-visual-no-local" );
			return;
		}

		if ( setup is not null && setup.IsValid() )
		{
			setup.SelectLocalDrone( selectedType );
			setup.SpawnPawnFor( local, PlayerRole.Pilot );
		}

		var pilot = scene.GetAllComponents<PilotSoldier>()
			.FirstOrDefault( p => !p.IsProxy && p.GameObject.Network.Owner?.Id == local.Id )
			?? scene.GetAllComponents<PilotSoldier>().FirstOrDefault( p => !p.IsProxy );

		if ( !pilot.IsValid() )
		{
			Log.Warning( "[RoundProbe] FPV visual probe could not find a local pilot pawn." );
			LogProbe( "fpv-visual-no-pilot" );
			return;
		}

		pilot.ChosenDrone = selectedType;
		var propProof = view.Equals( "PropProof", StringComparison.OrdinalIgnoreCase )
			|| view.Equals( "Proof", StringComparison.OrdinalIgnoreCase );

		var linkedDrones = scene.GetAllComponents<DroneBase>()
			.Where( drone => IsProbeDroneLinkedTo( drone, pilot, local.Id ) )
			.ToList();
		var existing = linkedDrones.FirstOrDefault( drone => drone.Type == selectedType && IsProbeDroneAlive( drone ) );
		foreach ( var linkedDrone in linkedDrones )
		{
			if ( existing.IsValid() && linkedDrone.GameObject.Id == existing.GameObject.Id ) continue;
			linkedDrone.GameObject.Destroy();
		}

		var droneObject = existing.IsValid() ? existing.GameObject : null;

		if ( !droneObject.IsValid() )
		{
			var prefabPath = selectedType switch
			{
				DroneType.Gps => "prefabs/drone_gps.prefab",
				DroneType.FiberOpticFpv => "prefabs/drone_fpv_fiber.prefab",
				_ => "prefabs/drone_fpv.prefab"
			};
			var prefab = GameObject.GetPrefab( prefabPath );
			if ( !prefab.IsValid() )
			{
				Log.Warning( $"[RoundProbe] {selectedType} drone prefab could not be loaded from {prefabPath}." );
				LogProbe( "fpv-visual-no-prefab" );
				return;
			}

			var spawnRotation = Rotation.FromYaw( pilot.GameObject.WorldRotation.Yaw() );
			var spawnPosition = pilot.GameObject.WorldPosition + spawnRotation.Forward * 120f + Vector3.Up * 72f;
			droneObject = prefab.Clone( new Transform( spawnPosition, spawnRotation ), name: $"{selectedType} Visual Probe - {local.DisplayName}" );

			var link = droneObject.Components.Get<PilotLink>( FindMode.EverythingInSelfAndDescendants );
			if ( link.IsValid() )
				link.PilotId = local.Id;

			var droneController = droneObject.Components.Get<DroneController>( FindMode.EverythingInSelfAndDescendants );
			if ( droneController.IsValid() )
			{
				var eyeAngles = droneController.EyeAngles;
				eyeAngles.yaw = spawnRotation.Yaw();
				droneController.EyeAngles = eyeAngles;
			}

			if ( Networking.IsActive )
				droneObject.NetworkSpawn( local );

			pilot.LinkedDroneId = droneObject.Id;
		}
		else
		{
			pilot.LinkedDroneId = droneObject.Id;
		}

		var deployer = pilot.Components.Get<DroneDeployer>( FindMode.EverythingInSelfAndDescendants );
		if ( deployer.IsValid() )
			deployer.DroneInFlight = true;

		var remote = pilot.Components.Get<RemoteController>( FindMode.EverythingInSelfAndDescendants );
		if ( remote.IsValid() )
		{
			remote.DroneViewActive = true;
			remote.SetDroneViewActive( true );
		}

		if ( propProof )
		{
			var proofRotation = Rotation.FromYaw( pilot.GameObject.WorldRotation.Yaw() );
			droneObject.WorldPosition = pilot.GameObject.WorldPosition + proofRotation.Forward * 220f + Vector3.Up * 120f;
			droneObject.WorldRotation = proofRotation;

			var body = droneObject.Components.Get<Rigidbody>( FindMode.EverythingInSelfAndDescendants );
			if ( body.IsValid() )
				body.Velocity = Vector3.Zero;

			var droneController = droneObject.Components.Get<DroneController>( FindMode.EverythingInSelfAndDescendants );
			if ( droneController.IsValid() )
			{
				droneController.EyeAngles = new Angles( 25f, proofRotation.Yaw(), 0f );
				droneController.BoostActive = false;
			}
		}

		var camera = droneObject.Components.Get<DroneCamera>( FindMode.EverythingInSelfAndDescendants );
		if ( camera.IsValid() )
		{
			var chaseProof = propProof
				|| view.Equals( "Chase", StringComparison.OrdinalIgnoreCase )
				|| view.Equals( "ThirdPerson", StringComparison.OrdinalIgnoreCase );
			camera.SetFirstPersonActive( !chaseProof );
			camera.ShowVisualInFirstPerson = true;
			if ( propProof )
			{
				camera.ChaseDistance = 115f;
				camera.ChaseHeight = 42f;
			}
		}

		Log.Info( $"[RoundProbe] FPV visual probe active: local pilot is flying {selectedType} with {view} visual proof enabled." );
		LogProbe( $"fpv-visual-active-{selectedType}-{view}" );
	}

	[ConCmd( "dvp_drone_launch_guard_probe" )]
	public static void DroneLaunchGuardProbe( string droneType = "Gps" )
	{
		if ( !Enum.TryParse<DroneType>( droneType, true, out var selectedType ) )
		{
			Log.Warning( $"[RoundProbe] Unknown DroneType '{droneType}'." );
			LogProbe( $"drone-launch-guard-unknown-{droneType}" );
			return;
		}

		if ( !Networking.IsHost )
		{
			Log.Warning( "[RoundProbe] dvp_drone_launch_guard_probe must run on the host." );
			LogProbe( "drone-launch-guard-not-host" );
			return;
		}

		var scene = Game.ActiveScene;
		var setup = Find<GameSetup>();
		var local = Connection.Local ?? Connection.All.FirstOrDefault();
		if ( scene is null || local is null )
		{
			Log.Warning( "[RoundProbe] Cannot run drone launch guard without an active scene and local connection." );
			LogProbe( "drone-launch-guard-no-local" );
			return;
		}

		if ( setup is not null && setup.IsValid() )
		{
			setup.SelectLocalDrone( selectedType );
			setup.SpawnPawnFor( local, PlayerRole.Pilot );
		}

		var pilot = scene.GetAllComponents<PilotSoldier>()
			.FirstOrDefault( p => !p.IsProxy && p.GameObject.Network.Owner?.Id == local.Id )
			?? scene.GetAllComponents<PilotSoldier>().FirstOrDefault( p => !p.IsProxy );

		if ( !pilot.IsValid() )
		{
			Log.Warning( "[RoundProbe] Drone launch guard could not find a local pilot pawn." );
			LogProbe( "drone-launch-guard-no-pilot" );
			return;
		}

		pilot.ChosenDrone = selectedType;
		var linkedDrones = scene.GetAllComponents<DroneBase>()
			.Where( drone => IsProbeDroneLinkedTo( drone, pilot, local.Id ) )
			.ToList();
		var existing = linkedDrones.FirstOrDefault( drone => drone.Type == selectedType && IsProbeDroneAlive( drone ) );
		foreach ( var linkedDrone in linkedDrones )
		{
			if ( existing.IsValid() && linkedDrone.GameObject.Id == existing.GameObject.Id ) continue;
			linkedDrone.GameObject.Destroy();
		}

		var droneObject = existing.IsValid() ? existing.GameObject : null;
		if ( !droneObject.IsValid() )
		{
			var prefabPath = selectedType switch
			{
				DroneType.Gps => "prefabs/drone_gps.prefab",
				DroneType.FiberOpticFpv => "prefabs/drone_fpv_fiber.prefab",
				_ => "prefabs/drone_fpv.prefab"
			};
			var prefab = GameObject.GetPrefab( prefabPath );
			if ( !prefab.IsValid() )
			{
				Log.Warning( $"[RoundProbe] {selectedType} drone prefab could not be loaded from {prefabPath}." );
				LogProbe( "drone-launch-guard-no-prefab" );
				return;
			}

			var spawnRotation = Rotation.FromYaw( pilot.GameObject.WorldRotation.Yaw() );
			var spawnPosition = pilot.GameObject.WorldPosition + spawnRotation.Forward * 180f + Vector3.Up * 90f;
			droneObject = prefab.Clone( new Transform( spawnPosition, spawnRotation ), name: $"{selectedType} Launch Guard Probe - {local.DisplayName}" );

			var link = droneObject.Components.Get<PilotLink>( FindMode.EverythingInSelfAndDescendants );
			if ( link.IsValid() )
				link.PilotId = local.Id;

			if ( Networking.IsActive )
				droneObject.NetworkSpawn( local );
		}

		pilot.LinkedDroneId = droneObject.Id;

		var deployer = pilot.Components.Get<DroneDeployer>( FindMode.EverythingInSelfAndDescendants );
		if ( !deployer.IsValid() )
		{
			Log.Warning( "[RoundProbe] Drone launch guard could not find a DroneDeployer." );
			LogProbe( "drone-launch-guard-no-deployer" );
			return;
		}

		deployer.DroneInFlight = false;
		deployer.LaunchReadyAt = 0f;
		var beforeCount = CountLinkedLiveDrones( scene, pilot, local.Id, selectedType );

		var requestedRotation = Rotation.FromYaw( pilot.GameObject.WorldRotation.Yaw() );
		var requestedPosition = pilot.GameObject.WorldPosition + requestedRotation.Forward * 240f + Vector3.Up * 90f;
		deployer.DebugLaunchDroneForProbe( local.Id, requestedPosition, requestedRotation, Vector3.Zero );

		var afterCount = CountLinkedLiveDrones( scene, pilot, local.Id, selectedType );
		var pass = beforeCount == 1 && afterCount == 1 && deployer.DroneInFlight;
		Log.Info( $"[RoundProbe] Drone launch guard {selectedType}: before={beforeCount} after={afterCount} droneInFlight={deployer.DroneInFlight} pass={pass}" );
		LogProbe( $"drone-launch-guard-{selectedType}-{(pass ? "pass" : "fail")}" );
	}

	static int CountLinkedLiveDrones( Scene scene, PilotSoldier pilot, Guid ownerId, DroneType selectedType )
	{
		return scene.GetAllComponents<DroneBase>()
			.Count( drone => drone.Type == selectedType && IsProbeDroneLinkedTo( drone, pilot, ownerId ) && IsProbeDroneAlive( drone ) );
	}

	static void DestroyExtraLocalPilotPawns( Scene scene, PilotSoldier keep, Guid ownerId )
	{
		foreach ( var pilot in scene.GetAllComponents<PilotSoldier>().ToList() )
		{
			if ( !pilot.IsValid() || !pilot.GameObject.IsValid() )
				continue;
			if ( keep.IsValid() && pilot.GameObject.Id == keep.GameObject.Id )
				continue;
			if ( pilot.IsProxy )
				continue;

			var owner = pilot.GameObject.Network.Owner?.Id ?? default;
			if ( owner != ownerId )
				continue;
			if ( !pilot.GameObject.Name.StartsWith( "Pilot -", StringComparison.Ordinal ) )
				continue;

			pilot.GameObject.Destroy();
		}
	}

	static bool IsProbeDroneLinkedTo( DroneBase drone, PilotSoldier pilot, Guid ownerId )
	{
		if ( !drone.IsValid() ) return false;

		if ( pilot.IsValid() && pilot.LinkedDroneId != default && drone.GameObject.Id == pilot.LinkedDroneId )
			return true;

		var link = drone.Components.Get<PilotLink>( FindMode.EverythingInSelfAndDescendants );
		return link.IsValid() && link.PilotId == ownerId;
	}

	static bool IsProbeDroneAlive( DroneBase drone )
	{
		if ( !drone.IsValid() ) return false;

		var health = drone.Components.Get<Health>() ?? drone.Components.GetInAncestors<Health>();
		return !health.IsValid() || !health.IsDead;
	}

	[ConCmd( "dvp_select_soldier" )]
	public static void SelectSoldier( string soldierClass = "Assault" )
	{
		if ( !Enum.TryParse<SoldierClass>( soldierClass, true, out var cls ) )
		{
			Log.Warning( $"[RoundProbe] Unknown SoldierClass '{soldierClass}'." );
			return;
		}

		var setup = Find<GameSetup>();
		if ( setup is null || !setup.IsValid() )
		{
			Log.Warning( "[RoundProbe] GameSetup not found." );
			return;
		}

		setup.SelectLocalSoldier( cls );
		LogProbe( $"select-soldier-{cls}" );
	}

	[ConCmd( "dvp_select_drone" )]
	public static void SelectDrone( string droneType = "Gps" )
	{
		if ( !Enum.TryParse<DroneType>( droneType, true, out var type ) )
		{
			Log.Warning( $"[RoundProbe] Unknown DroneType '{droneType}'." );
			return;
		}

		var setup = Find<GameSetup>();
		if ( setup is null || !setup.IsValid() )
		{
			Log.Warning( "[RoundProbe] GameSetup not found." );
			return;
		}

		setup.SelectLocalDrone( type );
		LogProbe( $"select-drone-{type}" );
	}

	[ConCmd( "dvp_kill_team" )]
	public static void KillTeam( string team = "Pilot" )
	{
		if ( !Networking.IsHost )
		{
			Log.Warning( "[RoundProbe] dvp_kill_team must run on the host." );
			LogProbe( $"kill-team-{team}-not-host" );
			return;
		}

		KillTeamInternal( team, "Console" );
	}

	[ConCmd( "dvp_connect_local" )]
	public static void ConnectLocal( string target = "127.0.0.1" )
	{
		if ( string.IsNullOrWhiteSpace( target ) )
		{
			Log.Warning( "[RoundProbe] dvp_connect_local requires a target." );
			return;
		}

		if ( Networking.IsActive )
			Networking.Disconnect();

		if ( ulong.TryParse( target, out var steamId ) )
			Networking.Connect( steamId );
		else
			Networking.Connect( target );
		Log.Info( $"[RoundProbe] Connecting to local target {target}." );
		LogProbe( "connect-local" );
	}

	[ConCmd( "dvp_round_autodrive" )]
	public static void EnableAutodrive( string mode = "host-pilot" )
	{
		if ( !Networking.IsHost )
		{
			Log.Warning( "[RoundProbe] dvp_round_autodrive must run on the host." );
			LogProbe( "autodrive-not-host" );
			return;
		}

		var setup = Find<GameSetup>();
		if ( setup is null || !setup.IsValid() )
		{
			Log.Warning( "[RoundProbe] GameSetup not found." );
			return;
		}

		setup.EditorAutodriveMode = mode;
		setup.EditorAutodriveToken++;
		_lastAutodriveToken = setup.EditorAutodriveToken;
		_lastAutodriveSelectionGeneration = -1;
		_autodriveEliminations = 0;
		Log.Info( $"[RoundProbe] Autodrive enabled mode={mode} token={setup.EditorAutodriveToken}" );
		LogProbe( "autodrive-enabled" );
	}

	[ConCmd( "dvp_round_autodrive_clear" )]
	public static void ClearAutodrive()
	{
		if ( Networking.IsHost )
		{
			var setup = Find<GameSetup>();
			if ( setup is not null && setup.IsValid() )
			{
				setup.EditorAutodriveMode = "";
				setup.EditorAutodriveToken++;
			}
		}

		_lastAutodriveToken = -1;
		_lastAutodriveSelectionGeneration = -1;
		_autodriveEliminations = 0;
		Log.Info( "[RoundProbe] Autodrive cleared." );
		LogProbe( "autodrive-cleared" );
	}

	public static void TickEditorAutodrive( GameSetup setup )
	{
		if ( !Game.IsEditor ) return;
		if ( setup is null || !setup.IsValid() ) return;
		if ( _timeSinceAutodrivePoll < 0.5f ) return;
		_timeSinceAutodrivePoll = 0f;

		var mode = setup.EditorAutodriveMode ?? "";
		if ( string.IsNullOrWhiteSpace( mode ) )
			return;

		if ( _lastAutodriveToken != setup.EditorAutodriveToken )
		{
			_lastAutodriveToken = setup.EditorAutodriveToken;
			_lastAutodriveSelectionGeneration = -1;
			_autodriveEliminations = 0;
		}

		if ( _lastAutodriveSelectionGeneration < setup.SelectionGeneration )
		{
			SelectLocalAutodriveLoadout( setup, mode );
			_lastAutodriveSelectionGeneration = setup.SelectionGeneration;
			LogProbe( $"autodrive-select-{setup.SelectionGeneration}" );
		}

		var round = Find<RoundManager>();
		if ( !Networking.IsHost || round is null || !round.IsValid() ) return;
		if ( round.State != RoundState.Active ) return;
		if ( _autodriveEliminations >= 1 ) return;

		KillTeamInternal( GetAutodriveKillTeam( mode ), "Autodrive" );
		_autodriveEliminations++;
	}

	public static string BuildSnapshot( string label = "manual", GameSetup context = null )
	{
		var scene = context?.Scene ?? Game.ActiveScene;
		var setup = context is not null && context.IsValid()
			? context
			: scene?.GetAllComponents<GameSetup>().FirstOrDefault() ?? Find<GameSetup>();
		var round = scene?.GetAllComponents<RoundManager>().FirstOrDefault() ?? Find<RoundManager>();
		var stats = scene?.GetAllComponents<GameStats>().FirstOrDefault() ?? Find<GameStats>();
		var health = scene?.GetAllComponents<Health>().ToList() ?? new List<Health>();
		var soldiers = scene?.GetAllComponents<SoldierBase>().ToList() ?? new List<SoldierBase>();
		var pilots = scene?.GetAllComponents<PilotSoldier>().ToList() ?? new List<PilotSoldier>();
		var drones = scene?.GetAllComponents<DroneBase>().ToList() ?? new List<DroneBase>();

		var setupText = setup is null || !setup.IsValid()
			? "setup=missing"
			: $"selection={setup.SelectionGeneration} localSelection={setup.LocalSelectionGeneration} pilots=[{JoinIds( setup.PilotTeam )}] soldiers=[{JoinIds( setup.SoldierTeam )}] autodrive={setup.EditorAutodriveMode}:{setup.EditorAutodriveToken}";

		var roundText = round is null || !round.IsValid()
			? "round=missing"
			: $"state={round.State} seconds={round.StateSecondsRemaining} wins={round.PilotWins}-{round.SoldierWins} last={round.LastWinnerInt}";

		var scoreText = stats is null || !stats.IsValid()
			? "score=missing"
			: $"score=[{string.Join( ";", stats.GetScoreboard().Select( s => $"{s.Name}:{s.Kills}/{s.Deaths}/{s.Score}" ) )}]";

		var pawnText = string.Join( ";", health.Select( h => $"{h.GameObject?.Name}:{ClassifyRole( h.GameObject )}:{h.GameObject?.Network.Owner?.Id}:{h.CurrentHealth:0}/{h.MaxHealth:0}:dead={h.IsDead}" ) );
		var connectionText = string.Join( ";", Connection.All.Select( c => $"{c.Id}:{c.DisplayName}:host={c.IsHost}:active={c.IsActive}:steam={c.SteamId}:owner={c.OwnerSteamId}:addr={c.Address}" ) );

		return
			$"label={label} editor={Game.IsEditor} playing={Game.IsPlaying} sceneEditor={scene?.IsEditor} netActive={Networking.IsActive} host={Networking.IsHost} client={Networking.IsClient} connecting={Networking.IsConnecting} " +
			$"connections={Connection.All.Count} local={Connection.Local?.Id}:{Connection.Local?.DisplayName}:steam={Connection.Local?.SteamId}:addr={Connection.Local?.Address} all=[{connectionText}] {roundText} {setupText} " +
			$"counts=soldiers:{soldiers.Count},pilots:{pilots.Count},drones:{drones.Count},health:{health.Count},alive:{health.Count( h => !h.IsDead )},dead:{health.Count( h => h.IsDead )} " +
			$"pawns=[{pawnText}] {scoreText}";
	}

	static void SelectLocalAutodriveLoadout( GameSetup setup, string mode )
	{
		var hostSoldier = mode.Equals( "host-soldier", StringComparison.OrdinalIgnoreCase );
		var localShouldPilot = Networking.IsHost ? !hostSoldier : hostSoldier;

		if ( localShouldPilot )
		{
			setup.SelectLocalDrone( Networking.IsHost ? DroneType.Gps : DroneType.Fpv );
			return;
		}

		setup.SelectLocalSoldier( SoldierClass.Assault );
	}

	static string GetAutodriveKillTeam( string mode )
	{
		return mode.Equals( "host-soldier", StringComparison.OrdinalIgnoreCase ) ? "Soldier" : "Pilot";
	}

	static void KillTeamInternal( string team, string source )
	{
		var scene = Game.ActiveScene;
		if ( scene is null ) return;

		var targetPilot = team.Equals( "Pilot", StringComparison.OrdinalIgnoreCase )
			|| team.Equals( "Pilots", StringComparison.OrdinalIgnoreCase );

		var targets = targetPilot
			? scene.GetAllComponents<PilotSoldier>().Select( c => c.GameObject ).ToList()
			: scene.GetAllComponents<SoldierBase>().Select( c => c.GameObject ).ToList();

		var attackerId = GetOpposingAttackerId( targetPilot );
		var killed = 0;
		foreach ( var go in targets.Distinct() )
		{
			var health = go.Components.Get<Health>( FindMode.EverythingInSelfAndDescendants )
				?? go.Components.GetInAncestors<Health>();
			if ( !health.IsValid() || health.IsDead )
				continue;

			health.TakeDamage( new DamageInfo
			{
				Amount = MathF.Max( health.CurrentHealth + 1000f, 10000f ),
				AttackerId = attackerId,
				Position = go.WorldPosition,
				WeaponName = $"{source} Round Probe",
			} );
			killed++;
		}

		Log.Info( $"[RoundProbe] {source} killed {killed} {(targetPilot ? "pilot" : "soldier")} pawn(s)." );
		LogProbe( $"kill-{team}-{killed}" );
	}

	static Guid GetOpposingAttackerId( bool targetPilot )
	{
		var setup = Find<GameSetup>();
		if ( setup is not null && setup.IsValid() )
		{
			var team = targetPilot ? setup.SoldierTeam : setup.PilotTeam;
			var id = team.FirstOrDefault();
			if ( id != default )
				return id;
		}

		return Connection.All.FirstOrDefault()?.Id ?? default;
	}

	static void LogProbe( string label )
	{
		Log.Info( $"[RoundProbe] {BuildSnapshot( label )}" );
	}

	static string ClassifyRole( GameObject go )
	{
		if ( go is null ) return "";
		if ( go.Components.Get<PilotSoldier>( FindMode.EverythingInSelfAndDescendants ).IsValid()
			|| go.Components.GetInAncestors<PilotSoldier>().IsValid() )
			return "Pilot";
		if ( go.Components.Get<SoldierBase>( FindMode.EverythingInSelfAndDescendants ).IsValid()
			|| go.Components.GetInAncestors<SoldierBase>().IsValid() )
			return "Soldier";
		if ( go.Components.Get<DroneBase>( FindMode.EverythingInSelfAndDescendants ).IsValid()
			|| go.Components.GetInAncestors<DroneBase>().IsValid() )
			return "Drone";
		if ( go.Components.Get<TrainingDummy>( FindMode.EverythingInSelfAndDescendants ).IsValid()
			|| go.Components.GetInAncestors<TrainingDummy>().IsValid() )
			return "TrainingDummy";
		return "Other";
	}

	static string JoinIds( IEnumerable<Guid> ids )
	{
		return string.Join( ",", ids.Select( id => id.ToString( "N" ) ) );
	}

	static T Find<T>() where T : Component
	{
		return Game.ActiveScene?.GetAllComponents<T>().FirstOrDefault();
	}
}
#endif
