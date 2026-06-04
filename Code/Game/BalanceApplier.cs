using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Applies central balance data to runtime clones. Keeping this outside
/// GameSetup and DroneDeployer prevents spawn flow from growing a second
/// responsibility every time balance gains a new tunable.
/// </summary>
public static class BalanceApplier
{
	public static void ApplyPilotGround( GameObject pawn, BalanceConfigResource config )
	{
		var settings = config?.PilotGround ?? SoldierBalanceSettings.PilotGroundDefaults();
		ApplyGroundPawn( pawn, settings );
		ApplyHitscan( pawn, settings.PrimaryWeapon );
	}

	public static void ApplySoldier( GameObject pawn, SoldierClass cls, BalanceConfigResource config )
	{
		var settings = config?.GetSoldier( cls ) ?? SoldierBalanceSettings.AssaultDefaults();
		ApplyGroundPawn( pawn, settings );

		switch ( cls )
		{
			case SoldierClass.CounterUav:
				ApplyJammer( pawn, settings.Jammer );
				ApplyFragGrenade( pawn, settings.Equipment );
				break;
			case SoldierClass.Heavy:
				ApplyShotgun( pawn, settings.PrimaryWeapon );
				ApplyEmpGrenade( pawn, settings.Equipment );
				break;
			default:
				ApplyHitscan( pawn, settings.PrimaryWeapon );
				ApplyChaffGrenade( pawn, settings.Equipment );
				break;
		}
	}

	public static void ApplyDrone( GameObject drone, DroneType type, BalanceConfigResource config )
	{
		var settings = config?.GetDrone( type ) ?? DroneBalanceSettings.GpsDefaults();
		if ( !drone.IsValid() ) return;

		var health = drone.Components.Get<Health>( FindMode.EverythingInSelfAndDescendants );
		if ( health.IsValid() )
		{
			health.MaxHealth = MathF.Max( 1f, settings.MaxHealth );
			health.CurrentHealth = health.MaxHealth;
			health.IsDead = false;
		}

		var controller = drone.Components.Get<DroneController>( FindMode.EverythingInSelfAndDescendants );
		if ( controller.IsValid() )
		{
			controller.MaxSpeed = MathF.Max( 1f, settings.MaxSpeed );
			controller.Acceleration = MathF.Max( 0.1f, settings.Acceleration );
			controller.BoostMultiplier = MathF.Max( 0.5f, settings.BoostMultiplier );
		}

		var identity = drone.Components.Get<DroneBase>( FindMode.EverythingInSelfAndDescendants );
		if ( identity.IsValid() )
			identity.JamSusceptibility = settings.JamSusceptibility.Clamp( 0f, 1f );

		var weapon = drone.Components.Get<DroneWeapon>( FindMode.EverythingInSelfAndDescendants );
		if ( weapon.IsValid() )
		{
			weapon.EnableHitscan = settings.EnableHitscan;
			weapon.HitscanDamage = MathF.Max( 0f, settings.HitscanDamage );
			weapon.HitscanRange = MathF.Max( 1f, settings.HitscanRange );
			weapon.HitscanInterval = MathF.Max( 0.01f, settings.HitscanInterval );
			weapon.EnableKamikaze = settings.EnableKamikaze;
			weapon.KamikazeRadius = MathF.Max( 0f, settings.KamikazeRadius );
			weapon.KamikazeDamage = MathF.Max( 0f, settings.KamikazeDamage );
			weapon.KamikazeFalloff = settings.KamikazeFalloff.Clamp( 0f, 1f );
		}
	}

	public static void ApplyTrainingDummy( GameObject dummy, PlayerRole role, BalanceConfigResource config )
	{
		if ( !dummy.IsValid() ) return;

		var settings = role == PlayerRole.Pilot
			? config?.PilotGround ?? SoldierBalanceSettings.PilotGroundDefaults()
			: config?.Assault ?? SoldierBalanceSettings.AssaultDefaults();

		var health = dummy.Components.Get<Health>( FindMode.EverythingInSelfAndDescendants );
		if ( health.IsValid() )
		{
			health.MaxHealth = MathF.Max( 1f, settings.MaxHealth );
			health.CurrentHealth = health.MaxHealth;
			health.IsDead = false;
		}
	}

	static void ApplyGroundPawn( GameObject pawn, SoldierBalanceSettings settings )
	{
		if ( !pawn.IsValid() || settings is null ) return;

		var health = pawn.Components.Get<Health>( FindMode.EverythingInSelfAndDescendants );
		if ( health.IsValid() )
		{
			health.MaxHealth = MathF.Max( 1f, settings.MaxHealth );
			health.CurrentHealth = health.MaxHealth;
			health.IsDead = false;
		}

		var controller = pawn.Components.Get<GroundPlayerController>( FindMode.EverythingInSelfAndDescendants );
		if ( controller.IsValid() )
		{
			controller.WalkSpeed = MathF.Max( 1f, settings.WalkSpeed );
			controller.SprintSpeed = MathF.Max( controller.WalkSpeed, settings.SprintSpeed );
		}
	}

	static void ApplyHitscan( GameObject pawn, WeaponBalanceSettings settings )
	{
		if ( settings is null ) return;

		var weapon = pawn.Components.Get<HitscanWeapon>( FindMode.EverythingInSelfAndDescendants );
		if ( !weapon.IsValid() ) return;

		weapon.Damage = MathF.Max( 0f, settings.Damage );
		weapon.FireInterval = MathF.Max( 0.01f, settings.FireInterval );
		weapon.MagazineSize = Math.Max( 1, settings.MagazineSize );
		weapon.StartingReserveAmmo = Math.Max( 0, settings.StartingReserveAmmo );
		weapon.ReloadSeconds = MathF.Max( 0.05f, settings.ReloadSeconds );
	}

	static void ApplyShotgun( GameObject pawn, WeaponBalanceSettings settings )
	{
		if ( settings is null ) return;

		var weapon = pawn.Components.Get<ShotgunWeapon>( FindMode.EverythingInSelfAndDescendants );
		if ( !weapon.IsValid() ) return;

		weapon.DamagePerPellet = MathF.Max( 0f, settings.DamagePerPellet );
		weapon.PelletCount = Math.Max( 1, settings.PelletCount );
		weapon.FireInterval = MathF.Max( 0.01f, settings.FireInterval );
		weapon.MagazineSize = Math.Max( 1, settings.MagazineSize );
		weapon.StartingReserveAmmo = Math.Max( 0, settings.StartingReserveAmmo );
		weapon.ReloadSeconds = MathF.Max( 0.05f, settings.ReloadSeconds );
	}

	static void ApplyJammer( GameObject pawn, JammerBalanceSettings settings )
	{
		if ( settings is null ) return;

		var jammer = pawn.Components.Get<DroneJammerGun>( FindMode.EverythingInSelfAndDescendants );
		if ( !jammer.IsValid() ) return;

		jammer.MaxRange = MathF.Max( 1f, settings.MaxRange );
		jammer.ConeHalfAngle = settings.ConeHalfAngle.Clamp( 1f, 45f );
		jammer.TickInterval = MathF.Max( 0.01f, settings.TickInterval );
		jammer.PulseDuration = MathF.Max( 0.01f, settings.PulseDuration );
		jammer.Strength = settings.Strength.Clamp( 0f, 1f );
	}

	static void ApplyChaffGrenade( GameObject pawn, GrenadeBalanceSettings settings )
	{
		if ( settings is null ) return;

		var grenade = pawn.Components.Get<ChaffGrenade>( FindMode.EverythingInSelfAndDescendants );
		if ( !grenade.IsValid() ) return;

		grenade.Radius = MathF.Max( 0f, settings.Radius );
		grenade.JamDuration = MathF.Max( 0f, settings.JamDuration );
		grenade.Strength = settings.Strength.Clamp( 0f, 1f );
		ApplyThrowable( grenade, settings );
	}

	static void ApplyEmpGrenade( GameObject pawn, GrenadeBalanceSettings settings )
	{
		if ( settings is null ) return;

		var grenade = pawn.Components.Get<EmpGrenade>( FindMode.EverythingInSelfAndDescendants );
		if ( !grenade.IsValid() ) return;

		grenade.Radius = MathF.Max( 0f, settings.Radius );
		grenade.JamDuration = MathF.Max( 0f, settings.JamDuration );
		grenade.Strength = settings.Strength.Clamp( 0f, 1f );
		ApplyThrowable( grenade, settings );
	}

	static void ApplyFragGrenade( GameObject pawn, GrenadeBalanceSettings settings )
	{
		if ( settings is null ) return;

		var grenade = pawn.Components.Get<FragGrenade>( FindMode.EverythingInSelfAndDescendants );
		if ( !grenade.IsValid() ) return;

		grenade.Radius = MathF.Max( 0f, settings.Radius );
		grenade.Damage = MathF.Max( 0f, settings.Damage );
		grenade.Falloff = settings.Falloff.Clamp( 0f, 1f );
		ApplyThrowable( grenade, settings );
	}

	static void ApplyThrowable( ThrowableGrenade grenade, GrenadeBalanceSettings settings )
	{
		grenade.FuseSeconds = MathF.Max( 0.05f, settings.FuseSeconds );
		grenade.Cooldown = MathF.Max( 0f, settings.Cooldown );
	}
}
