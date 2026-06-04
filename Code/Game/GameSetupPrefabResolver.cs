using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Keeps prefab and authored-loadout path resolution out of GameSetup so the
/// setup component can stay focused on connection, team, and spawn flow.
/// </summary>
public static class GameSetupPrefabResolver
{
	public static GameObject ResolvePilotGroundPrefab( GameSetup setup )
	{
		if ( setup is null ) return null;
		if ( setup.PilotGroundPrefab.IsValid() ) return setup.PilotGroundPrefab;
		if ( !string.IsNullOrWhiteSpace( setup.PilotGroundPrefabPath ) )
		{
			var p = GameObject.GetPrefab( setup.PilotGroundPrefabPath );
			if ( p.IsValid() ) return p;
		}

		// Fallback to the legacy soldier prefab so pilots at least spawn.
		return setup.SoldierPrefab.IsValid()
			? setup.SoldierPrefab
			: GameObject.GetPrefab( setup.SoldierPrefabPath );
	}

	public static GameObject ResolveTrainingDummyPrefab( GameSetup setup )
	{
		if ( setup is null ) return null;
		if ( setup.TrainingDummyPrefab.IsValid() ) return setup.TrainingDummyPrefab;
		if ( !string.IsNullOrWhiteSpace( setup.TrainingDummyPrefabPath ) )
		{
			var p = GameObject.GetPrefab( setup.TrainingDummyPrefabPath );
			if ( p.IsValid() ) return p;
		}

		return null;
	}

	public static GameObject ResolveSoldierPrefab( GameSetup setup, SoldierClass cls )
	{
		if ( setup is null ) return null;

		var definition = setup.GetAuthoredSoldierLoadoutDefinition( cls );
		var definitionPrefab = ResolvePrefabPath( definition?.PrefabPath );
		if ( definitionPrefab.IsValid() )
			return definitionPrefab;

		var (inspector, path) = cls switch
		{
			SoldierClass.Assault => (setup.AssaultPrefab, setup.AssaultPrefabPath),
			SoldierClass.CounterUav => (setup.CounterUavPrefab, setup.CounterUavPrefabPath),
			SoldierClass.Heavy => (setup.HeavyPrefab, setup.HeavyPrefabPath),
			_ => (setup.SoldierPrefab, setup.SoldierPrefabPath),
		};

		if ( inspector.IsValid() ) return inspector;
		if ( !string.IsNullOrWhiteSpace( path ) )
		{
			var p = GameObject.GetPrefab( path );
			if ( p.IsValid() ) return p;
		}

		return setup.SoldierPrefab.IsValid()
			? setup.SoldierPrefab
			: GameObject.GetPrefab( setup.SoldierPrefabPath );
	}

	public static GameObject ResolveDronePrefab( GameSetup setup, DroneType type )
	{
		if ( setup is null ) return null;

		var definition = setup.GetAuthoredDroneLoadoutDefinition( type );
		var definitionPrefab = ResolvePrefabPath( definition?.PrefabPath );
		if ( definitionPrefab.IsValid() )
			return definitionPrefab;

		var (inspector, path) = type switch
		{
			DroneType.Gps => (setup.GpsDronePrefab, setup.GpsDronePrefabPath),
			DroneType.Fpv => (setup.FpvDronePrefab, setup.FpvDronePrefabPath),
			DroneType.FiberOpticFpv => (setup.FiberOpticFpvDronePrefab, setup.FiberOpticFpvDronePrefabPath),
			_ => (setup.DronePrefab, setup.DronePrefabPath),
		};

		if ( inspector.IsValid() ) return inspector;
		if ( !string.IsNullOrWhiteSpace( path ) )
		{
			var p = GameObject.GetPrefab( path );
			if ( p.IsValid() ) return p;
		}

		return setup.DronePrefab.IsValid()
			? setup.DronePrefab
			: GameObject.GetPrefab( setup.DronePrefabPath );
	}

	static GameObject ResolvePrefabPath( string prefabPath )
	{
		if ( string.IsNullOrWhiteSpace( prefabPath ) )
			return null;

		var prefab = GameObject.GetPrefab( prefabPath );
		return prefab.IsValid() ? prefab : null;
	}
}
