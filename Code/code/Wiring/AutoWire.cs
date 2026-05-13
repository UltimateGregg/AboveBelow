using Sandbox;
using Sandbox.Citizen;
using System.Linq;

namespace DroneVsPlayers;

public class AutoWireHelper : Component
{
	protected override void OnAwake()
	{
		WireGameManager();
		WireDronePrefab( "prefabs/drone.prefab" );
		WireDronePrefab( "prefabs/drone_gps.prefab" );
		WireDronePrefab( "prefabs/drone_fpv.prefab" );
		WireDronePrefab( "prefabs/drone_fpv_fiber.prefab" );

		WireSoldierPrefab( "prefabs/soldier.prefab" );
		WireSoldierPrefab( "prefabs/soldier_assault.prefab" );
		WireSoldierPrefab( "prefabs/soldier_counter_uav.prefab" );
		WireSoldierPrefab( "prefabs/soldier_heavy.prefab" );
		WireSoldierPrefab( "prefabs/pilot_ground.prefab" );
		Destroy();
	}

	void WireGameManager()
	{
		var gameManager = Scene.GetAllObjects( false ).FirstOrDefault( x => x.Name == "GameManager" );
		if ( gameManager == null ) return;

		var setup = gameManager.Components.Get<GameSetup>();
		var roundMgr = gameManager.Components.Get<RoundManager>();
		var rules = gameManager.Components.Get<GameRules>();
		var stats = gameManager.Components.Get<GameStats>();

		if ( setup != null && roundMgr != null )
		{
			setup.SoldierPrefab = GameObject.GetPrefab( "prefabs/soldier.prefab" );
			setup.DronePrefab = GameObject.GetPrefab( "prefabs/drone.prefab" );

			setup.AssaultPrefab = GameObject.GetPrefab( "prefabs/soldier_assault.prefab" );
			setup.CounterUavPrefab = GameObject.GetPrefab( "prefabs/soldier_counter_uav.prefab" );
			setup.HeavyPrefab = GameObject.GetPrefab( "prefabs/soldier_heavy.prefab" );
			setup.PilotGroundPrefab = GameObject.GetPrefab( "prefabs/pilot_ground.prefab" );
			setup.TrainingDummyPrefab = GameObject.GetPrefab( "prefabs/training_dummy.prefab" );

			setup.GpsDronePrefab = GameObject.GetPrefab( "prefabs/drone_gps.prefab" );
			setup.FpvDronePrefab = GameObject.GetPrefab( "prefabs/drone_fpv.prefab" );
			setup.FiberOpticFpvDronePrefab = GameObject.GetPrefab( "prefabs/drone_fpv_fiber.prefab" );

			setup.Round = roundMgr;
			setup.Rules = rules;
			roundMgr.Setup = setup;
			roundMgr.Rules = rules;
			roundMgr.Stats = stats;
			Log.Info( "GameManager wiring complete!" );
		}
	}

	void WireDronePrefab( string path )
	{
		var root = GameObject.GetPrefab( path );
		if ( !root.IsValid() ) return;

		var controller = root.Components.Get<DroneController>();
		var camera = root.Components.Get<DroneCamera>();
		var weapon = root.Components.Get<DroneWeapon>();
		var jammer = root.Components.Get<JammingReceiver>();
		var pilotLink = root.Components.Get<PilotLink>();
		var fiber = root.Components.Get<FiberCable>();
		var droneBase = root.Components.Get<DroneBase>( FindMode.EverythingInSelfAndDescendants );

		if ( controller != null )
		{
			controller.VisualModel = root.Children.FirstOrDefault( x => x.Name == "Visual" );
		}

		if ( camera != null )
		{
			camera.Drone = controller;
			camera.CameraSocket = root.Children.FirstOrDefault( x => x.Name == "CameraSocket" );
		}

		if ( weapon != null )
		{
			weapon.Drone = controller;
			weapon.MuzzleSocket = root.Children.FirstOrDefault( x => x.Name == "MuzzleSocket" );
			weapon.TracerPrefab = GameObject.GetPrefab( "prefabs/tracer_default.prefab" );
			weapon.ExplosionPrefab = GameObject.GetPrefab( "models/effects/explosion_med.prefab" );
		}

		if ( jammer != null )
		{
			jammer.Drone = controller;
			jammer.DroneBase = droneBase;
		}

		if ( pilotLink != null )
		{
			pilotLink.Drone = controller;
			pilotLink.DroneBase = droneBase;
			pilotLink.Body = root.Components.Get<Rigidbody>();
			pilotLink.ExplosionPrefab = GameObject.GetPrefab( "models/effects/explosion_med.prefab" );
		}

		if ( fiber != null )
		{
			fiber.Link = pilotLink;
			fiber.Line = root.Components.Get<LineRenderer>();
		}

		Log.Info( $"Drone prefab wiring complete: {path}" );
	}

	void WireSoldierPrefab( string path )
	{
		var root = GameObject.GetPrefab( path );
		if ( !root.IsValid() ) return;

		var controller = root.Components.Get<GroundPlayerController>();
		var weaponObject = FindDescendantByName( root, "Weapon" );
		var grenadeObject = FindDescendantByName( root, "Grenade" );
		var droneDeployerObject = FindDescendantByName( root, "DroneDeployer" );

		if ( controller != null )
		{
			controller.Body = root.Children.FirstOrDefault( x => x.Name == "Body" );
			controller.Eye = root.Children.FirstOrDefault( x => x.Name == "Eye" );

			var animHelper = controller.Body?.Components.Get<CitizenAnimationHelper>();
			if ( animHelper != null )
			{
				controller.AnimationHelper = animHelper;
				var renderer = controller.Body.Components.Get<SkinnedModelRenderer>();
				if ( renderer != null )
				{
					animHelper.Target = renderer;
				}
			}
		}

		// Wire whatever weapon is present (HitscanWeapon, ShotgunWeapon, DroneJammerGun).
		if ( weaponObject != null )
		{
			var muzzle = weaponObject.Children.FirstOrDefault( x => x.Name == "MuzzleSocket" );
			var visual = weaponObject.Children.FirstOrDefault( x => x.Name == "WeaponVisual" );
			var flash = muzzle?.Children.FirstOrDefault( x => x.Name == "MuzzleFlash" );

			var hit = weaponObject.Components.Get<HitscanWeapon>();
			if ( hit != null )
			{
				hit.MuzzleSocket = muzzle;
				hit.WeaponVisual = visual;
				hit.MuzzleFlash = flash?.Components.Get<PointLight>();
			}

			var shotgun = weaponObject.Components.Get<ShotgunWeapon>();
			if ( shotgun != null ) shotgun.MuzzleSocket = muzzle;

			var jammerGun = weaponObject.Components.Get<DroneJammerGun>();
			if ( jammerGun != null ) jammerGun.MuzzleSocket = muzzle;
		}

		// Wire grenade explosion FX if present.
		if ( grenadeObject != null )
		{
			var frag = grenadeObject.Components.Get<FragGrenade>();
			if ( frag != null )
				frag.ExplosionPrefab = GameObject.GetPrefab( "models/effects/explosion_med.prefab" );
		}

		// Wire the pilot's held drone/controller item if present.
		if ( droneDeployerObject != null )
		{
			var deployer = droneDeployerObject.Components.Get<DroneDeployer>();
			if ( deployer != null )
			{
				deployer.LeftHandVisual = FindDescendantByName( droneDeployerObject, "LeftHand" );
				deployer.RightHandVisual = FindDescendantByName( droneDeployerObject, "RightHand" );
				deployer.LeftHandIkTarget = FindDescendantByName( droneDeployerObject, "LeftHandIk" );
				deployer.RightHandIkTarget = FindDescendantByName( droneDeployerObject, "RightHandIk" );
				deployer.GpsDronePrefab = GameObject.GetPrefab( "prefabs/drone_gps.prefab" );
				deployer.FpvDronePrefab = GameObject.GetPrefab( "prefabs/drone_fpv.prefab" );
				deployer.FiberOpticFpvDronePrefab = GameObject.GetPrefab( "prefabs/drone_fpv_fiber.prefab" );
			}
		}

		Log.Info( $"Soldier prefab wiring complete: {path}" );
	}

	static GameObject FindDescendantByName( GameObject root, string name )
	{
		foreach ( var child in root.Children )
		{
			if ( child.Name == name )
				return child;

			var descendant = FindDescendantByName( child, name );
			if ( descendant.IsValid() )
				return descendant;
		}

		return null;
	}
}
