using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Central balance data for ABOVE / BELOW. Prefab values remain useful editor
/// defaults, but runtime spawns should receive gameplay tuning from this
/// resource so balance passes do not require editing several prefab graphs.
/// </summary>
[AssetType( Name = "DVP Balance Config", Extension = "dvpbalance", Category = "Drone vs Players", Flags = AssetTypeFlags.IncludeThumbnails )]
public sealed class BalanceConfigResource : GameResource
{
	[Property] public MatchBalanceSettings Match { get; set; } = new();

	[Property] public SoldierBalanceSettings Assault { get; set; } = SoldierBalanceSettings.AssaultDefaults();
	[Property] public SoldierBalanceSettings CounterUav { get; set; } = SoldierBalanceSettings.CounterUavDefaults();
	[Property] public SoldierBalanceSettings Heavy { get; set; } = SoldierBalanceSettings.HeavyDefaults();
	[Property] public SoldierBalanceSettings PilotGround { get; set; } = SoldierBalanceSettings.PilotGroundDefaults();

	[Property] public DroneBalanceSettings GpsDrone { get; set; } = DroneBalanceSettings.GpsDefaults();
	[Property] public DroneBalanceSettings FpvDrone { get; set; } = DroneBalanceSettings.FpvDefaults();
	[Property] public DroneBalanceSettings FiberFpvDrone { get; set; } = DroneBalanceSettings.FiberFpvDefaults();

	public SoldierBalanceSettings GetSoldier( SoldierClass cls ) => cls switch
	{
		SoldierClass.CounterUav => CounterUav ?? SoldierBalanceSettings.CounterUavDefaults(),
		SoldierClass.Heavy => Heavy ?? SoldierBalanceSettings.HeavyDefaults(),
		_ => Assault ?? SoldierBalanceSettings.AssaultDefaults(),
	};

	public DroneBalanceSettings GetDrone( DroneType type ) => type switch
	{
		DroneType.Fpv => FpvDrone ?? DroneBalanceSettings.FpvDefaults(),
		DroneType.FiberOpticFpv => FiberFpvDrone ?? DroneBalanceSettings.FiberFpvDefaults(),
		_ => GpsDrone ?? DroneBalanceSettings.GpsDefaults(),
	};
}

public sealed class MatchBalanceSettings
{
	[Property] public int RoundTimeSeconds { get; set; } = 180;
	[Property] public int MinPlayersToStart { get; set; } = 1;
	[Property] public float CountdownSeconds { get; set; } = 5f;
	[Property] public float RoundEndScreenSeconds { get; set; } = 5f;
	[Property] public int PilotTeamSize { get; set; } = 3;
	[Property] public int SoldierTeamSize { get; set; } = 4;
}

public sealed class SoldierBalanceSettings
{
	[Property] public float MaxHealth { get; set; } = 100f;
	[Property] public float WalkSpeed { get; set; } = 110f;
	[Property] public float SprintSpeed { get; set; } = 320f;

	[Property] public WeaponBalanceSettings PrimaryWeapon { get; set; } = new();
	[Property] public JammerBalanceSettings Jammer { get; set; } = new();
	[Property] public GrenadeBalanceSettings Equipment { get; set; } = new();

	public static SoldierBalanceSettings AssaultDefaults() => new()
	{
		MaxHealth = 100f,
		WalkSpeed = 110f,
		SprintSpeed = 320f,
		PrimaryWeapon = new WeaponBalanceSettings
		{
			Damage = 18f,
			FireInterval = 0.08f,
			MagazineSize = 30,
			StartingReserveAmmo = 120,
			ReloadSeconds = 1.65f
		},
		Equipment = new GrenadeBalanceSettings
		{
			Radius = 600f,
			JamDuration = 3f,
			Strength = 1f,
			FuseSeconds = 1.5f,
			Cooldown = 4f
		}
	};

	public static SoldierBalanceSettings CounterUavDefaults() => new()
	{
		MaxHealth = 100f,
		WalkSpeed = 110f,
		SprintSpeed = 320f,
		Jammer = new JammerBalanceSettings
		{
			MaxRange = 4000f,
			ConeHalfAngle = 12f,
			TickInterval = 0.1f,
			PulseDuration = 0.3f,
			Strength = 1f
		},
		Equipment = new GrenadeBalanceSettings
		{
			Radius = 320f,
			Damage = 130f,
			Falloff = 0.6f,
			FuseSeconds = 1.5f,
			Cooldown = 4f
		}
	};

	public static SoldierBalanceSettings HeavyDefaults() => new()
	{
		MaxHealth = 150f,
		WalkSpeed = 90f,
		SprintSpeed = 240f,
		PrimaryWeapon = new WeaponBalanceSettings
		{
			DamagePerPellet = 9f,
			PelletCount = 8,
			FireInterval = 0.7f,
			MagazineSize = 6,
			StartingReserveAmmo = 24,
			ReloadSeconds = 2.4f
		},
		Equipment = new GrenadeBalanceSettings
		{
			Radius = 1100f,
			JamDuration = 6f,
			Strength = 1f,
			FuseSeconds = 2.5f,
			Cooldown = 8f
		}
	};

	public static SoldierBalanceSettings PilotGroundDefaults() => new()
	{
		MaxHealth = 60f,
		WalkSpeed = 110f,
		SprintSpeed = 260f,
		PrimaryWeapon = new WeaponBalanceSettings
		{
			Damage = 12f,
			FireInterval = 0.07f,
			MagazineSize = 30,
			StartingReserveAmmo = 120,
			ReloadSeconds = 1.65f
		}
	};
}

public sealed class DroneBalanceSettings
{
	[Property] public float MaxHealth { get; set; } = 60f;
	[Property] public float MaxSpeed { get; set; } = 900f;
	[Property] public float Acceleration { get; set; } = 7f;
	[Property] public float BoostMultiplier { get; set; } = 1.6f;
	[Property, Range( 0f, 1f )] public float JamSusceptibility { get; set; } = 1f;

	[Property] public bool EnableHitscan { get; set; } = true;
	[Property] public float HitscanDamage { get; set; } = 7f;
	[Property] public float HitscanRange { get; set; } = 7500f;
	[Property] public float HitscanInterval { get; set; } = 0.25f;

	[Property] public bool EnableKamikaze { get; set; }
	[Property] public float KamikazeRadius { get; set; } = 320f;
	[Property] public float KamikazeDamage { get; set; } = 200f;
	[Property] public float KamikazeFalloff { get; set; } = 0.6f;

	public static DroneBalanceSettings GpsDefaults() => new()
	{
		MaxHealth = 60f,
		MaxSpeed = 900f,
		Acceleration = 7f,
		JamSusceptibility = 1f,
		EnableHitscan = true,
		HitscanDamage = 7f,
		HitscanRange = 7500f,
		HitscanInterval = 0.25f,
		EnableKamikaze = false,
		KamikazeRadius = 320f,
		KamikazeDamage = 200f,
		KamikazeFalloff = 0.6f
	};

	public static DroneBalanceSettings FpvDefaults() => new()
	{
		MaxHealth = 45f,
		MaxSpeed = 1300f,
		Acceleration = 14f,
		JamSusceptibility = 0.85f,
		EnableHitscan = false,
		EnableKamikaze = true,
		KamikazeRadius = 320f,
		KamikazeDamage = 200f,
		KamikazeFalloff = 0.6f
	};

	public static DroneBalanceSettings FiberFpvDefaults() => new()
	{
		MaxHealth = 45f,
		MaxSpeed = 1100f,
		Acceleration = 12f,
		JamSusceptibility = 0f,
		EnableHitscan = false,
		EnableKamikaze = true,
		KamikazeRadius = 320f,
		KamikazeDamage = 200f,
		KamikazeFalloff = 0.6f
	};
}

public sealed class WeaponBalanceSettings
{
	[Property] public float Damage { get; set; }
	[Property] public float DamagePerPellet { get; set; }
	[Property] public int PelletCount { get; set; }
	[Property] public float FireInterval { get; set; }
	[Property] public int MagazineSize { get; set; }
	[Property] public int StartingReserveAmmo { get; set; }
	[Property] public float ReloadSeconds { get; set; }
}

public sealed class JammerBalanceSettings
{
	[Property] public float MaxRange { get; set; } = 4000f;
	[Property] public float ConeHalfAngle { get; set; } = 12f;
	[Property] public float TickInterval { get; set; } = 0.1f;
	[Property] public float PulseDuration { get; set; } = 0.3f;
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;
}

public sealed class GrenadeBalanceSettings
{
	[Property] public float Radius { get; set; }
	[Property] public float Damage { get; set; }
	[Property] public float Falloff { get; set; } = 0.6f;
	[Property] public float JamDuration { get; set; }
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;
	[Property] public float FuseSeconds { get; set; } = 1.5f;
	[Property] public float Cooldown { get; set; } = 4f;
}
