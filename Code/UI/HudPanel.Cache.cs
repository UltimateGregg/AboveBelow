using Sandbox;
using System.Linq;

namespace DroneVsPlayers;

// Per-frame cache for the HUD's scene lookups. RefreshHudCache() runs as the
// first step of OnUpdate; the razor's render-path properties read these fields
// instead of re-querying the scene (the old property getters issued dozens of
// scene-wide GetAllComponents calls per frame across markup and BuildHash).
public partial class HudPanel
{
	// Match-lifetime singletons: resolved lazily and only re-queried when the
	// cached reference is invalidated (scene reload / hotload).
	RoundManager _round;
	GameSetup _setup;
	GameStats _stats;
	KillFeedTracker _killFeed;
	SunGlareSource _sunGlareSource;

	// Pawn-lifetime refs: re-resolved once per frame so death, respawn, and
	// drone deploys swap the HUD over just like the old per-render queries.
	GroundPlayerController _localGround;
	PilotSoldier _localPilot;
	DroneController _localDrone;
	DroneCamera _localDroneCamera;
	RemoteController _localRemote;
	CameraComponent _sceneCamera;
	WorldInteractionPrompt _worldPrompt;

	// Derived from the pawn refs above — cheap hierarchy lookups done once.
	Health _localHealth;
	JammingReceiver _localJammer;
	DroneBase _localDroneBase;
	DroneWeapon _localDroneWeapon;
	HitscanWeapon _activeRifle;
	ShotgunWeapon _activeShotgun;
	DroneJammerGun _activeJammerGun;

	T EnsureValid<T>( ref T cached ) where T : Component
	{
		if ( !cached.IsValid() )
			cached = Scene.GetAllComponents<T>().FirstOrDefault();

		return cached;
	}

	void RefreshHudCache()
	{
		_localGround = Scene.GetAllComponents<GroundPlayerController>().FirstOrDefault( g => !g.IsProxy );
		_localPilot = Scene.GetAllComponents<PilotSoldier>().FirstOrDefault( p => !p.IsProxy );
		_localDrone = Scene.GetAllComponents<DroneController>().FirstOrDefault( d => !d.IsProxy );
		_localDroneCamera = Scene.GetAllComponents<DroneCamera>().FirstOrDefault( c => !c.IsProxy );
		_localRemote = Scene.GetAllComponents<RemoteController>().FirstOrDefault( r => !r.IsProxy );
		_sceneCamera = Scene.GetAllComponents<CameraComponent>().FirstOrDefault();

		_localJammer = _localDrone.IsValid() ? _localDrone.Components.Get<JammingReceiver>() : null;
		_localDroneBase = _localDrone.IsValid() ? _localDrone.Components.Get<DroneBase>() : null;
		_localDroneWeapon = _localDrone.IsValid() ? _localDrone.Components.Get<DroneWeapon>() : null;

		_localHealth = ResolveLocalHealth();
		ResolveActiveHeldItems();

		// Resolved last: depends on the camera and pawn fields assigned above.
		_worldPrompt = ResolveWorldPrompt();
	}

	Health ResolveLocalHealth()
	{
		// Drone first, then ground player. Owner == not proxy == this client.
		if ( _localDrone.IsValid() )
			return _localDrone.Components.Get<Health>() ?? _localDrone.Components.GetInAncestors<Health>();

		if ( _localGround.IsValid() )
			return _localGround.Components.Get<Health>() ?? _localGround.Components.GetInAncestors<Health>();

		return null;
	}

	void ResolveActiveHeldItems()
	{
		_activeRifle = null;
		_activeShotgun = null;
		_activeJammerGun = null;

		if ( !_localGround.IsValid() )
			return;

		var components = _localGround.GameObject.Components;
		var selectedSlot = SelectedLoadoutSlot;
		var loadout = components.Get<SoldierLoadout>( FindMode.EverythingInSelfAndDescendants );
		if ( loadout.IsValid() )
			selectedSlot = loadout.ActiveSlot;

		_activeRifle = components
			.GetAll<HitscanWeapon>( FindMode.EverythingInSelfAndDescendants )
			.FirstOrDefault( weapon => weapon.IsValid() && weapon.Slot == selectedSlot );
		_activeShotgun = components
			.GetAll<ShotgunWeapon>( FindMode.EverythingInSelfAndDescendants )
			.FirstOrDefault( weapon => weapon.IsValid() && weapon.Slot == selectedSlot );
		_activeJammerGun = components.Get<DroneJammerGun>( FindMode.EverythingInSelfAndDescendants );
	}

	WorldInteractionPrompt ResolveWorldPrompt()
	{
		if ( GameplayUiBlocked )
			return null;

		var cameraPosition = _sceneCamera.IsValid() ? _sceneCamera.WorldPosition : Vector3.Zero;
		return Scene.GetAllComponents<WorldInteractionPrompt>()
			.Where( prompt => prompt.IsValid() && prompt.IsAvailableFor( cameraPosition, LocalRole ) )
			.OrderBy( prompt => prompt.WorldPosition.Distance( cameraPosition ) )
			.FirstOrDefault();
	}
}
