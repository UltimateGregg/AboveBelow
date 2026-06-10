using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace DroneVsPlayers;

// Pawn spawning: pilot/soldier pawn creation, despawn, spawn-point picking, solo training dummies, team voice.
public sealed partial class GameSetup
{
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

	// Role-only respawn helper for round rotation and legacy callers.
	public void RespawnWithSelectedLoadout( Connection channel, PlayerRole role )
	{
		if ( channel is null ) return;

		if ( role == PlayerRole.Pilot )
			SpawnPilotPawn( channel, GetSelectedDroneType( channel.Id ) );
		else if ( role == PlayerRole.Soldier )
			SpawnSoldierPawn( channel, GetSelectedSoldierClass( channel.Id ) );
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
}
