using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Local-only first-person held-item renderer. It spawns a viewmodel weapon or
/// item for the local player, then spawns Facepunch first-person arms on top of
/// that item. Facepunch stock weapon viewmodels provide arms animation and, for
/// custom project weapons, stay hidden while copied project visuals are aligned
/// to the stock hand anchors and existing held-item grip points.
/// </summary>
[Title( "First Person Viewmodel" )]
[Category( "Drone vs Players/Player" )]
[Icon( "front_hand" )]
public sealed partial class FirstPersonViewmodel : Component
{
	const string ViewmodelRootPrefabPath = "prefabs/items/local_first_person_viewmodel.prefab";
	const string ViewmodelArmsPrefabPath = "prefabs/items/viewmodel_arms.prefab";
	const string ViewmodelStockWeaponPrefabPath = "prefabs/items/viewmodel_stock_weapon.prefab";
	const string ViewmodelCustomVisualPrefabPath = "prefabs/items/viewmodel_custom_visual.prefab";
	const string ViewmodelStaticItemPrefabPath = "prefabs/items/viewmodel_static_item.prefab";

	[Property] public string ArmsModelPath { get; set; } = "facepunch/v_first_person_arms_human";
	[Property] public string ArmsFallbackModelPath { get; set; } = "models/first_person/first_person_arms_preview.vmdl";

	[Property] public string AssaultRifleViewmodelPath { get; set; } = "facepunch/v_m4a1";
	[Property] public string PilotSmgViewmodelPath { get; set; } = "facepunch/v_mp5";
	[Property] public string ShotgunViewmodelPath { get; set; } = "facepunch/v_spaghellim4";
	[Property] public string FragGrenadeViewmodelPath { get; set; } = "facepunch/v_he_grenade";
	[Property] public string ChaffGrenadeViewmodelPath { get; set; } = "facepunch/v_smoke_grenade";
	[Property] public string EmpGrenadeViewmodelPath { get; set; } = "facepunch/v_decoy_grenade";

	[Property] public string AssaultRifleCustomModelPath { get; set; } = "models/weapons/assault_rifle_m4.vmdl";
	[Property] public string PilotSmgCustomModelPath { get; set; } = "models/weapons/smg_mp7.vmdl";
	[Property] public string ShotgunCustomModelPath { get; set; } = "models/shotgun.vmdl";
	[Property] public string JammerCustomModelPath { get; set; } = "models/jammer_gun.vmdl";
	string JammerStockAnimationPath => AssaultRifleViewmodelPath;

	[Property] public Vector3 StockViewmodelOffset { get; set; } = new( 8f, 0f, 0f );
	[Property] public Angles StockViewmodelRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 CustomM4ViewmodelOffset { get; set; } = new( 2f, 0f, 0f );
	[Property] public Angles CustomM4ViewmodelRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 CustomM4ViewmodelScale { get; set; } = new( 1f, 1f, 1f );
	[Property] public Vector3 CustomSmgViewmodelOffset { get; set; } = Vector3.Zero;
	[Property] public Angles CustomSmgViewmodelRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 CustomSmgViewmodelScale { get; set; } = new( 0.5f, 0.5f, 0.5f );
	[Property] public Vector3 CustomShotgunViewmodelOffset { get; set; } = new( 2f, 0f, 0f );
	[Property] public Angles CustomShotgunViewmodelRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 CustomShotgunViewmodelScale { get; set; } = new( 1f, 1f, 1f );
	[Property] public Vector3 CustomJammerViewmodelOffset { get; set; } = Vector3.Zero;
	[Property] public Angles CustomJammerViewmodelRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 CustomJammerViewmodelScale { get; set; } = new( 1f, 1f, 1f );
	[Property, Range( 1f, 60f )] public float StaticArmFollowRate { get; set; } = 28f;
	/// <summary>
	/// Eye-relative anchor (forward, right, up) for the pilot deployer's stock
	/// first-person arms. The arms originate here near the camera and the hands
	/// IK out to the controller (left) and held drone (right) grip targets.
	/// </summary>
	[Property] public Vector3 DeployerArmsEyeOffset { get; set; } = new( 0f, 0f, -6f );

	GameObject _root;
	GameObject _weaponObject;
	GameObject _customVisualRoot;
	GameObject _armsObject;
	SkinnedModelRenderer _weaponRenderer;
	SkinnedModelRenderer _armsRenderer;
	string _activeKey = "";
	ViewmodelRenderMode _renderMode = ViewmodelRenderMode.StaticFallback;
	bool _wasReloading;
	bool _customVisualBoneAttached;
	int _customVisualPoseFrames;
	Vector3 _customVisualScale = Vector3.One;
	TimeSince _timeSinceLastAttack = 10f;

	readonly List<StaticVisual> _staticVisuals = new();

	enum ViewmodelRenderMode
	{
		StaticFallback,
		StockVisible,
		CustomVisibleStockAnimated
	}

	struct StaticVisual
	{
		public ModelRenderer Source;
		public GameObject CopyObject;
		public ModelRenderer CopyRenderer;
	}

	struct HeldItem
	{
		public Component Owner;
		public GameObject Root;
		public GameObject VisualTarget;
		public GameObject HiddenStaticVisualRoot;
		public GameObject LeftHandTarget;
		public GameObject RightHandTarget;
		public GameObject MuzzleTarget;
		public string Key;
		public string StockModelPath;
		public string CustomModelPath;
		public ViewmodelRenderMode RenderMode;
		public bool HasStockViewmodel;
		public bool TwoHanded;
		public bool IsAds;
		public bool IsReloading;
		public bool IsEmpty;
		public bool AttackPressed;
		public bool AttackDown;
		public bool ReloadPressed;
		public Vector3 MoveInput;
		public Vector3 CustomViewmodelOffset;
		public Angles CustomViewmodelRotation;
		public Vector3 CustomViewmodelScale;
		public bool UseEyeArmsAnchor;
		public Vector3 ArmsEyeOffset;
	}

	public bool IsViewmodelActive => _root.IsValid() && _root.Enabled && HasVisibleViewmodel();

	public static bool ShouldHideWorldHeldItem( Component owner, bool selected )
	{
		if ( owner is null || !selected || owner.IsProxy )
			return false;

		var pc = owner.Components.GetInAncestors<GroundPlayerController>();
		return pc.IsValid() && pc.UseLocalFirstPersonViewmodel && pc.LocalFirstPersonViewmodelActive;
	}

	protected override void OnUpdate()
	{
		var pc = Components.Get<GroundPlayerController>();
		if ( !CanRenderFor( pc ) || !FindSelectedHeldItem( pc, out var item ) )
		{
			SetInactive( pc );
			return;
		}

		EnsureViewmodel( item );
		UpdateRootPose( pc );
		UpdateStaticVisuals( item );
		UpdateArmsForStaticFallback( item );
		UpdateStockAnimParameters( pc, item );

		pc.LocalFirstPersonViewmodelActive = IsViewmodelActive;
	}

	protected override void OnDisabled()
	{
		base.OnDisabled();

		var pc = Components.Get<GroundPlayerController>();
		if ( pc.IsValid() )
			pc.LocalFirstPersonViewmodelActive = false;

		DestroyViewmodel();
	}

	protected override void OnDestroy()
	{
		base.OnDestroy();
		DestroyViewmodel();
	}

	bool CanRenderFor( GroundPlayerController pc )
	{
		return pc.IsValid()
			&& pc.UseLocalFirstPersonViewmodel
			&& pc.FirstPerson
			&& pc.Eye.IsValid()
			&& !IsProxy;
	}

	void SetInactive( GroundPlayerController pc )
	{
		if ( pc.IsValid() )
			pc.LocalFirstPersonViewmodelActive = false;

		if ( _root.IsValid() )
			_root.Enabled = false;
	}

	bool IsDroneViewActive()
	{
		var remote = Components.Get<RemoteController>();
		return remote.IsValid() && remote.DroneViewActive;
	}

	bool HasVisibleViewmodel()
	{
		if ( _renderMode == ViewmodelRenderMode.StockVisible
			&& _weaponRenderer.IsValid()
			&& _weaponRenderer.Model is not null
			&& _weaponRenderer.Model.IsValid )
			return true;

		if ( _armsRenderer.IsValid() && _armsRenderer.Model is not null && _armsRenderer.Model.IsValid )
			return true;

		return _staticVisuals.Any( x => x.CopyRenderer.IsValid() && x.CopyRenderer.Model is not null && x.CopyRenderer.Model.IsValid );
	}
}
