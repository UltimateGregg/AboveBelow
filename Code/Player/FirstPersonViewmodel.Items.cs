using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

// Held-item registry: maps each selected held item type to its viewmodel descriptor. Add new weapon types here.
public sealed partial class FirstPersonViewmodel
{
	bool FindSelectedHeldItem( GroundPlayerController pc, out HeldItem item )
	{
		item = default;
		var moveInput = Input.AnalogMove;

		foreach ( var deployer in Components.GetAll<DroneDeployer>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !deployer.IsValid() || !deployer.IsSelected || IsDroneViewActive() )
				continue;

			var pilot = deployer.Components.GetInAncestors<PilotSoldier>();
			var chosenDrone = pilot.IsValid() ? pilot.ChosenDrone : DroneType.Fpv;

			// The pilot holds two different objects in two different hands, so it
			// uses the stock first-person arms with per-hand IK (left hand grips
			// the controller, right hand grips the held drone) rather than the
			// bone-merged single-weapon grip the hunters use.
			item = new HeldItem
			{
				Owner = deployer,
				Root = deployer.GameObject,
				HiddenStaticVisualRoot = deployer.DroneInFlight ? deployer.RightHandVisual : null,
				LeftHandTarget = deployer.LeftHandIkTarget,
				RightHandTarget = deployer.RightHandIkTarget,
				Key = $"deployer:{deployer.GameObject.Id}:{chosenDrone}:{deployer.DroneInFlight}",
				RenderMode = ViewmodelRenderMode.StaticFallback,
				TwoHanded = true,
				UseEyeArmsAnchor = true,
				ArmsEyeOffset = DeployerArmsEyeOffset,
				AttackPressed = Input.Pressed( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				MoveInput = moveInput
			};
			return true;
		}

		foreach ( var weapon in Components.GetAll<HitscanWeapon>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !weapon.IsValid() || !weapon.IsSelected )
				continue;

			var isSmg = weapon.WeaponDisplayName?.Contains( "MP7", StringComparison.OrdinalIgnoreCase ) == true;
			item = new HeldItem
			{
				Owner = weapon,
				Root = weapon.GameObject,
				VisualTarget = weapon.WeaponVisual,
				LeftHandTarget = weapon.LeftHandIkTarget,
				RightHandTarget = weapon.RightHandIkTarget,
				MuzzleTarget = weapon.MuzzleSocket,
				Key = $"hitscan:{weapon.GameObject.Id}:{(isSmg ? "mp7" : "m4a1")}",
				StockModelPath = isSmg ? PilotSmgViewmodelPath : AssaultRifleViewmodelPath,
				CustomModelPath = isSmg ? PilotSmgCustomModelPath : AssaultRifleCustomModelPath,
				RenderMode = ViewmodelRenderMode.CustomVisibleStockAnimated,
				HasStockViewmodel = true,
				TwoHanded = !isSmg,
				IsAds = pc.IsAds,
				IsReloading = weapon.IsReloading,
				IsEmpty = weapon.AmmoInMagazine <= 0,
				AttackPressed = Input.Down( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				ReloadPressed = Input.Pressed( "Reload" ),
				MoveInput = moveInput,
				CustomViewmodelOffset = isSmg ? CustomSmgViewmodelOffset : CustomM4ViewmodelOffset,
				CustomViewmodelRotation = isSmg ? CustomSmgViewmodelRotation : CustomM4ViewmodelRotation,
				CustomViewmodelScale = isSmg ? CustomSmgViewmodelScale : CustomM4ViewmodelScale
			};
			return true;
		}

		foreach ( var shotgun in Components.GetAll<ShotgunWeapon>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !shotgun.IsValid() || !shotgun.IsSelected )
				continue;

			item = new HeldItem
			{
				Owner = shotgun,
				Root = shotgun.GameObject,
				VisualTarget = shotgun.WeaponVisual,
				LeftHandTarget = shotgun.LeftHandIkTarget,
				RightHandTarget = shotgun.RightHandIkTarget,
				MuzzleTarget = shotgun.MuzzleSocket,
				Key = $"shotgun:{shotgun.GameObject.Id}",
				StockModelPath = ShotgunViewmodelPath,
				CustomModelPath = ShotgunCustomModelPath,
				RenderMode = ViewmodelRenderMode.CustomVisibleStockAnimated,
				HasStockViewmodel = true,
				TwoHanded = true,
				IsAds = pc.IsAds,
				IsReloading = shotgun.IsReloading,
				IsEmpty = shotgun.AmmoInMagazine <= 0,
				AttackPressed = Input.Pressed( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				ReloadPressed = Input.Pressed( "Reload" ),
				MoveInput = moveInput,
				CustomViewmodelOffset = CustomShotgunViewmodelOffset,
				CustomViewmodelRotation = CustomShotgunViewmodelRotation,
				CustomViewmodelScale = CustomShotgunViewmodelScale
			};
			return true;
		}

		foreach ( var jammer in Components.GetAll<DroneJammerGun>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !jammer.IsValid() || !jammer.IsSelected )
				continue;

			item = new HeldItem
			{
				Owner = jammer,
				Root = jammer.GameObject,
				VisualTarget = jammer.WeaponVisual,
				LeftHandTarget = jammer.LeftHandIkTarget,
				RightHandTarget = jammer.RightHandIkTarget,
				MuzzleTarget = jammer.MuzzleSocket,
				Key = $"jammer:{jammer.GameObject.Id}",
				StockModelPath = JammerStockAnimationPath,
				CustomModelPath = JammerCustomModelPath,
				RenderMode = ViewmodelRenderMode.CustomVisibleStockAnimated,
				HasStockViewmodel = true,
				TwoHanded = true,
				IsAds = pc.IsAds,
				AttackPressed = Input.Pressed( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				MoveInput = moveInput,
				CustomViewmodelOffset = CustomJammerViewmodelOffset,
				CustomViewmodelRotation = CustomJammerViewmodelRotation,
				CustomViewmodelScale = CustomJammerViewmodelScale
			};
			return true;
		}

		foreach ( var grenade in Components.GetAll<ThrowableGrenade>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !grenade.IsValid() || !grenade.IsSelected || grenade.IsArmed )
				continue;

			item = new HeldItem
			{
				Owner = grenade,
				Root = grenade.GameObject,
				LeftHandTarget = grenade.LeftHandIkTarget,
				RightHandTarget = grenade.RightHandIkTarget,
				Key = $"grenade:{grenade.GetType().Name}:{grenade.GameObject.Id}",
				StockModelPath = GetGrenadeViewmodelPath( grenade ),
				RenderMode = ViewmodelRenderMode.StockVisible,
				HasStockViewmodel = true,
				TwoHanded = false,
				AttackPressed = Input.Pressed( grenade.ThrowInput ),
				AttackDown = Input.Down( grenade.ThrowInput ),
				MoveInput = moveInput
			};
			return true;
		}

		return false;
	}

	string GetGrenadeViewmodelPath( ThrowableGrenade grenade )
	{
		return grenade switch
		{
			FragGrenade => FragGrenadeViewmodelPath,
			ChaffGrenade => ChaffGrenadeViewmodelPath,
			EmpGrenade => EmpGrenadeViewmodelPath,
			_ => FragGrenadeViewmodelPath
		};
	}
}
