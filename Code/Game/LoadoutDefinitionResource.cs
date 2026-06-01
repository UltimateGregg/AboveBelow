using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Editor-authored metadata for a playable soldier class or drone variant.
/// Runtime network state still uses SoldierClass / DroneType enums; this
/// resource only supplies UI, preview, and optional prefab-path data.
/// </summary>
[AssetType( Name = "DVP Loadout Definition", Extension = "dvploadout", Category = "Drone vs Players", Flags = AssetTypeFlags.IncludeThumbnails )]
public sealed class LoadoutDefinitionResource : GameResource
{
	[Property] public PlayerRole Role { get; set; } = PlayerRole.Soldier;
	[Property] public SoldierClass SoldierClass { get; set; } = SoldierClass.Assault;
	[Property] public DroneType DroneType { get; set; } = DroneType.Gps;

	[Property] public string DisplayName { get; set; } = "Loadout";
	[Property] public string ShortDescription { get; set; } = "";
	[Property] public string LongDescription { get; set; } = "";
	[Property] public string PrimaryLabel { get; set; } = "Primary";
	[Property] public string PrimaryDetail { get; set; } = "";
	[Property] public string EquipmentLabel { get; set; } = "Equipment";
	[Property] public string EquipmentDetail { get; set; } = "";
	[Property] public string CounterplayHint { get; set; } = "";
	[Property] public Color AccentColor { get; set; } = Color.White;

	[Property, ResourceType( "prefab" )] public string PrefabPath { get; set; } = "";
	[Property, ResourceType( "vmdl" )] public string PreviewModelPath { get; set; } = "";
	[Property, ResourceType( "vmdl" )] public string HeldModelPath { get; set; } = "";
	[Property, ResourceType( "png" )] public string PreviewImagePath { get; set; } = "";

	public bool IsSoldierDefinition => Role == PlayerRole.Soldier;
	public bool IsDroneDefinition => Role == PlayerRole.Pilot;

	public int StableHash => HashCode.Combine(
		HashCode.Combine(
			Role,
			SoldierClass,
			DroneType,
			DisplayName ?? "",
			ShortDescription ?? "",
			PrimaryLabel ?? "",
			PrimaryDetail ?? "",
			EquipmentLabel ?? "" ),
		HashCode.Combine(
			EquipmentDetail ?? "",
			PrefabPath ?? "",
			PreviewModelPath ?? "",
			HeldModelPath ?? "",
			PreviewImagePath ?? "" ) );
}

public static class LoadoutCatalog
{
	static readonly LoadoutDefinitionResource[] SoldierFallbacks =
	{
		Soldier(
			SoldierClass.Assault,
			"Assault",
			"Rifle answer to fiber",
			"Reliable mid-range fire against tethered FPV pressure.",
			"M4 Rifle",
			"30-round automatic rifle",
			"Chaff Grenade",
			"Radio disruption and visual cover",
			"prefabs/soldier_assault.prefab",
			"models/assault_rifle_m4.vmdl" ),

		Soldier(
			SoldierClass.CounterUav,
			"Counter-UAV",
			"Jammer answer to GPS",
			"Cone jammer specialist that denies RF drone control.",
			"Drone Jammer",
			"Short cone RF denial",
			"Frag Grenade",
			"Area damage against ground targets",
			"prefabs/soldier_counter_uav.prefab",
			"models/jammer_gun.vmdl" ),

		Soldier(
			SoldierClass.Heavy,
			"Heavy",
			"EMP answer to FPV",
			"Close-range hunter built around burst damage and EMP denial.",
			"Tactical Shotgun",
			"High pellet burst",
			"EMP Grenade",
			"Drone stun and electronics denial",
			"prefabs/soldier_heavy.prefab",
			"models/shotgun_tactical.vmdl" ),
	};

	static readonly LoadoutDefinitionResource[] DroneFallbacks =
	{
		Drone(
			DroneType.Gps,
			"GPS Drone",
			"Long range vs heavy",
			"Stable recon drone with strong endurance and full RF vulnerability.",
			"Drone Launcher",
			"Deploy and enter camera",
			"RF Link",
			"Long range, jam susceptible",
			"prefabs/drone_gps.prefab",
			"models/drone_high.vmdl" ),

		Drone(
			DroneType.Fpv,
			"FPV Drone",
			"Fast dive vs assault",
			"Agile short-range FPV platform for quick strike runs.",
			"Drone Launcher",
			"Deploy and enter camera",
			"Video Link",
			"Fast, jam susceptible",
			"prefabs/drone_fpv.prefab",
			"models/drone_fpv.vmdl" ),

		Drone(
			DroneType.FiberOpticFpv,
			"Fiber FPV",
			"RF immune vs jammer",
			"Tethered FPV platform that ignores RF jamming pressure.",
			"Drone Launcher",
			"Deploy and enter camera",
			"Fiber Link",
			"RF immune, tether visible",
			"prefabs/drone_fpv_fiber.prefab",
			"models/drone_fpv_fiber.vmdl" ),
	};

	public static LoadoutDefinitionResource FindSoldier( IEnumerable<LoadoutDefinitionResource> definitions, SoldierClass cls )
	{
		return definitions?
			.Where( d => d is not null && d.IsSoldierDefinition && d.SoldierClass == cls )
			.LastOrDefault()
			?? SoldierFallbacks.First( d => d.SoldierClass == cls );
	}

	public static LoadoutDefinitionResource FindDrone( IEnumerable<LoadoutDefinitionResource> definitions, DroneType type )
	{
		return definitions?
			.Where( d => d is not null && d.IsDroneDefinition && d.DroneType == type )
			.LastOrDefault()
			?? DroneFallbacks.First( d => d.DroneType == type );
	}

	public static IReadOnlyList<LoadoutDefinitionResource> Fallbacks =>
		SoldierFallbacks.Concat( DroneFallbacks ).ToArray();

	static LoadoutDefinitionResource Soldier(
		SoldierClass cls,
		string name,
		string shortDescription,
		string longDescription,
		string primaryLabel,
		string primaryDetail,
		string equipmentLabel,
		string equipmentDetail,
		string prefabPath,
		string previewModelPath )
	{
		return new LoadoutDefinitionResource
		{
			Role = PlayerRole.Soldier,
			SoldierClass = cls,
			DisplayName = name,
			ShortDescription = shortDescription,
			LongDescription = longDescription,
			PrimaryLabel = primaryLabel,
			PrimaryDetail = primaryDetail,
			EquipmentLabel = equipmentLabel,
			EquipmentDetail = equipmentDetail,
			PrefabPath = prefabPath,
			PreviewModelPath = previewModelPath,
			HeldModelPath = previewModelPath,
			AccentColor = new Color( 1f, 0.61f, 0.21f )
		};
	}

	static LoadoutDefinitionResource Drone(
		DroneType type,
		string name,
		string shortDescription,
		string longDescription,
		string primaryLabel,
		string primaryDetail,
		string equipmentLabel,
		string equipmentDetail,
		string prefabPath,
		string previewModelPath )
	{
		return new LoadoutDefinitionResource
		{
			Role = PlayerRole.Pilot,
			DroneType = type,
			DisplayName = name,
			ShortDescription = shortDescription,
			LongDescription = longDescription,
			PrimaryLabel = primaryLabel,
			PrimaryDetail = primaryDetail,
			EquipmentLabel = equipmentLabel,
			EquipmentDetail = equipmentDetail,
			PrefabPath = prefabPath,
			PreviewModelPath = previewModelPath,
			HeldModelPath = previewModelPath,
			AccentColor = new Color( 0.3f, 0.82f, 1f )
		};
	}
}
