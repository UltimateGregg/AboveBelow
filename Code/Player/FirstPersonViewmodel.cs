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
public sealed class FirstPersonViewmodel : Component
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

	GameObject _root;
	GameObject _weaponObject;
	GameObject _customVisualRoot;
	GameObject _armsObject;
	SkinnedModelRenderer _weaponRenderer;
	SkinnedModelRenderer _armsRenderer;
	string _activeKey = "";
	ViewmodelRenderMode _renderMode = ViewmodelRenderMode.StaticFallback;
	bool _wasReloading;
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

	void EnsureViewmodel( HeldItem item )
	{
		if ( _root.IsValid() && _activeKey == item.Key )
		{
			_root.Enabled = true;
			return;
		}

		DestroyViewmodel();

		_activeKey = item.Key;
		var built = item.RenderMode switch
		{
			ViewmodelRenderMode.StockVisible => item.HasStockViewmodel && BuildStockWeaponViewmodel( item ),
			ViewmodelRenderMode.CustomVisibleStockAnimated => BuildCustomAnimatedViewmodel( item ),
			_ => false
		};

		if ( !built )
			BuildStaticItemViewmodel( item );

		if ( _root.IsValid() )
			_root.Enabled = true;
	}

	bool BuildStockWeaponViewmodel( HeldItem item )
	{
		var weaponModel = TryLoadModel( item.StockModelPath );
		if ( weaponModel is null || !weaponModel.IsValid )
			return false;

		CreateRoot();

		_weaponObject = CreateStockWeaponObject( $"Viewmodel Weapon - {item.Key}" );

		_weaponRenderer.Model = weaponModel;
		_weaponRenderer.RenderType = ModelRenderer.ShadowRenderType.On;
		_weaponRenderer.UseAnimGraph = true;
		_weaponRenderer.Parameters.Set( "b_deploy_skip", true );
		_weaponRenderer.Parameters.Set( "skeleton", 0 );
		_weaponRenderer.Parameters.Set( "b_twohanded", item.TwoHanded );

		CreateArmsRenderer( _weaponRenderer );
		_renderMode = ViewmodelRenderMode.StockVisible;
		return true;
	}

	bool BuildCustomAnimatedViewmodel( HeldItem item )
	{
		var weaponModel = TryLoadModel( item.StockModelPath );
		if ( weaponModel is null || !weaponModel.IsValid )
			return false;

		CreateRoot();

		_weaponObject = CreateStockWeaponObject( $"Hidden Stock Animation Driver - {item.Key}" );

		_weaponRenderer.Model = weaponModel;
		_weaponRenderer.UseAnimGraph = true;
		_weaponRenderer.Parameters.Set( "b_deploy_skip", true );
		_weaponRenderer.Parameters.Set( "skeleton", 0 );
		_weaponRenderer.Parameters.Set( "b_twohanded", item.TwoHanded );
		HideStockAnimationDriver();

		_customVisualRoot = CreateViewmodelContainer( ViewmodelCustomVisualPrefabPath, $"Custom Viewmodel Visual - {item.Key}" );

		if ( !AddCustomAnimatedVisualCopies( item, _customVisualRoot ) )
			AddModelPathFallback( item, _customVisualRoot );

		CreateArmsRenderer( _weaponRenderer );
		_renderMode = ViewmodelRenderMode.CustomVisibleStockAnimated;
		return true;
	}

	void HideStockAnimationDriver()
	{
		if ( !_weaponRenderer.IsValid() )
			return;

		_weaponRenderer.RenderType = ModelRenderer.ShadowRenderType.Off;

		if ( _weaponRenderer.SceneObject is { } sceneObject )
			sceneObject.RenderingEnabled = false;
	}

	void BuildStaticItemViewmodel( HeldItem item )
	{
		CreateRoot();

		_weaponObject = CreateViewmodelContainer( ViewmodelStaticItemPrefabPath, $"Viewmodel Item - {item.Key}" );

		AddStaticVisualCopies( item, _weaponObject );
		CreateArmsRenderer( null );
		_renderMode = ViewmodelRenderMode.StaticFallback;
	}

	bool AddStaticVisualCopies( HeldItem item, GameObject parent )
	{
		var copiedAny = false;
		foreach ( var source in item.Root.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !source.IsValid() || source.Model is null || !source.Model.IsValid )
				continue;
			if ( IsSameOrDescendant( source.GameObject, item.HiddenStaticVisualRoot ) )
				continue;

			var copyObject = new GameObject( parent, true, source.GameObject.Name )
			{
				NetworkMode = NetworkMode.Never
			};
			copyObject.LocalPosition = source.GameObject.LocalPosition;
			copyObject.LocalRotation = source.GameObject.LocalRotation;
			copyObject.LocalScale = source.GameObject.LocalScale;

			var copyRenderer = copyObject.Components.Create<ModelRenderer>();
			copyRenderer.Model = source.Model;
			copyRenderer.MaterialOverride = source.MaterialOverride;
			copyRenderer.RenderType = ModelRenderer.ShadowRenderType.On;

			_staticVisuals.Add( new StaticVisual
			{
				Source = source,
				CopyObject = copyObject,
				CopyRenderer = copyRenderer
			} );
			copiedAny = true;
		}

		return copiedAny;
	}

	static bool IsSameOrDescendant( GameObject candidate, GameObject root )
	{
		if ( !candidate.IsValid() || !root.IsValid() )
			return false;

		var current = candidate;
		while ( current.IsValid() )
		{
			if ( current == root )
				return true;

			current = current.Parent;
		}

		return false;
	}

	bool AddCustomAnimatedVisualCopies( HeldItem item, GameObject parent )
	{
		var visualRoot = item.VisualTarget.IsValid() ? item.VisualTarget : item.Root;
		if ( !visualRoot.IsValid() )
			return false;

		var copiedAny = false;
		foreach ( var source in visualRoot.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !source.IsValid() || source.Model is null || !source.Model.IsValid )
				continue;

			var copyObject = new GameObject( parent, true, source.GameObject.Name )
			{
				NetworkMode = NetworkMode.Never
			};

			var sourceIsWeaponRoot = source.GameObject == item.Root;
			copyObject.LocalPosition = sourceIsWeaponRoot ? Vector3.Zero : source.GameObject.LocalPosition;
			copyObject.LocalRotation = sourceIsWeaponRoot ? Rotation.Identity : source.GameObject.LocalRotation;
			copyObject.LocalScale = sourceIsWeaponRoot ? Vector3.One : source.GameObject.LocalScale;

			var copyRenderer = copyObject.Components.Create<ModelRenderer>();
			copyRenderer.Model = source.Model;
			copyRenderer.MaterialOverride = source.MaterialOverride;
			copyRenderer.RenderType = ModelRenderer.ShadowRenderType.On;

			_staticVisuals.Add( new StaticVisual
			{
				Source = source,
				CopyObject = copyObject,
				CopyRenderer = copyRenderer
			} );
			copiedAny = true;
		}

		return copiedAny;
	}

	void AddModelPathFallback( HeldItem item, GameObject parent )
	{
		var customModel = TryLoadModel( item.CustomModelPath );
		if ( customModel is null || !customModel.IsValid )
			return;

		var copyObject = new GameObject( parent, true, "WeaponVisual" )
		{
			NetworkMode = NetworkMode.Never
		};

		var copyRenderer = copyObject.Components.Create<ModelRenderer>();
		copyRenderer.Model = customModel;
		copyRenderer.RenderType = ModelRenderer.ShadowRenderType.On;

		_staticVisuals.Add( new StaticVisual
		{
			Source = null,
			CopyObject = copyObject,
			CopyRenderer = copyRenderer
		} );
	}

	void CreateRoot()
	{
		var prefab = GameObject.GetPrefab( ViewmodelRootPrefabPath );
		_root = prefab.IsValid()
			? prefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), null, true, "Local First Person Viewmodel" )
			: new GameObject( true, "Local First Person Viewmodel" );

		_root.NetworkMode = NetworkMode.Never;
	}

	GameObject CreateStockWeaponObject( string name )
	{
		var prefab = GameObject.GetPrefab( ViewmodelStockWeaponPrefabPath );
		var weaponObject = prefab.IsValid()
			? prefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), _root, true, name )
			: new GameObject( _root, true, name );

		weaponObject.NetworkMode = NetworkMode.Never;
		_weaponRenderer = weaponObject.Components.Get<SkinnedModelRenderer>();
		if ( !_weaponRenderer.IsValid() )
			_weaponRenderer = weaponObject.Components.Create<SkinnedModelRenderer>();

		return weaponObject;
	}

	GameObject CreateViewmodelContainer( string prefabPath, string name )
	{
		var prefab = GameObject.GetPrefab( prefabPath );
		var container = prefab.IsValid()
			? prefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), _root, true, name )
			: new GameObject( _root, true, name );

		container.NetworkMode = NetworkMode.Never;
		return container;
	}

	void CreateArmsRenderer( SkinnedModelRenderer boneMergeTarget )
	{
		var armsModel = TryLoadModel( ArmsModelPath );
		if ( armsModel is null || !armsModel.IsValid )
			armsModel = TryLoadModel( ArmsFallbackModelPath );

		if ( armsModel is null || !armsModel.IsValid )
			return;

		var armsPrefab = GameObject.GetPrefab( ViewmodelArmsPrefabPath );
		_armsObject = armsPrefab.IsValid()
			? armsPrefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), _root, true, "Viewmodel Arms" )
			: new GameObject( _root, true, "Viewmodel Arms" );

		_armsObject.NetworkMode = NetworkMode.Never;
		_armsRenderer = _armsObject.Components.Get<SkinnedModelRenderer>();
		if ( !_armsRenderer.IsValid() )
			_armsRenderer = _armsObject.Components.Create<SkinnedModelRenderer>();

		_armsRenderer.Model = armsModel;
		_armsRenderer.RenderType = ModelRenderer.ShadowRenderType.On;
		_armsRenderer.UseAnimGraph = boneMergeTarget is null;
		_armsRenderer.BoneMergeTarget = boneMergeTarget;
		_armsRenderer.Parameters.Set( "b_deploy_skip", true );
		_armsRenderer.Parameters.Set( "b_grab", true );
		_armsRenderer.Parameters.Set( "skeleton", 0 );
	}

	static Model TryLoadModel( string path )
	{
		if ( string.IsNullOrWhiteSpace( path ) )
			return null;

		try
		{
			return IsCloudReference( path )
				? LoadFacepunchCloudModel( path )
				: Model.Load( path );
		}
		catch ( Exception e )
		{
			Log.Warning( $"First-person viewmodel could not load '{path}': {e.Message}" );
			return null;
		}
	}

	static bool IsCloudReference( string path )
	{
		return path.StartsWith( "facepunch/", StringComparison.OrdinalIgnoreCase )
			|| path.StartsWith( "facepunch.", StringComparison.OrdinalIgnoreCase )
			|| path.StartsWith( "https://sbox.game/", StringComparison.OrdinalIgnoreCase );
	}

	static Model LoadFacepunchCloudModel( string ident )
	{
		return ident switch
		{
			"facepunch/v_first_person_arms_human" => Cloud.Model( "facepunch/v_first_person_arms_human" ),
			"facepunch/v_m4a1" => Cloud.Model( "facepunch/v_m4a1" ),
			"facepunch/v_mp5" => Cloud.Model( "facepunch/v_mp5" ),
			"facepunch/v_spaghellim4" => Cloud.Model( "facepunch/v_spaghellim4" ),
			"facepunch/v_he_grenade" => Cloud.Model( "facepunch/v_he_grenade" ),
			"facepunch/v_smoke_grenade" => Cloud.Model( "facepunch/v_smoke_grenade" ),
			"facepunch/v_decoy_grenade" => Cloud.Model( "facepunch/v_decoy_grenade" ),
			_ => null
		};
	}

	void UpdateRootPose( GroundPlayerController pc )
	{
		if ( !_root.IsValid() || !pc.Eye.IsValid() )
			return;

		var eyeRot = pc.Eye.WorldRotation;
		var targetPos = pc.Eye.WorldPosition
			+ eyeRot.Forward * StockViewmodelOffset.x
			+ eyeRot.Right * StockViewmodelOffset.y
			+ eyeRot.Up * StockViewmodelOffset.z;
		var targetRot = eyeRot * StockViewmodelRotationOffset.ToRotation();

		_root.WorldPosition = targetPos;
		_root.WorldRotation = targetRot;
	}

	void UpdateStaticVisuals( HeldItem item )
	{
		if ( _renderMode == ViewmodelRenderMode.StockVisible )
			return;

		if ( _renderMode == ViewmodelRenderMode.CustomVisibleStockAnimated )
		{
			UpdateCustomAnimatedVisual( item );
			return;
		}

		foreach ( var visual in _staticVisuals )
		{
			if ( !visual.Source.IsValid() || !visual.CopyObject.IsValid() || !visual.CopyRenderer.IsValid() )
				continue;

			visual.CopyObject.WorldPosition = visual.Source.GameObject.WorldPosition;
			visual.CopyObject.WorldRotation = visual.Source.GameObject.WorldRotation;
			visual.CopyObject.WorldScale = visual.Source.GameObject.WorldScale;
			visual.CopyRenderer.Model = visual.Source.Model;
			visual.CopyRenderer.MaterialOverride = visual.Source.MaterialOverride;
			visual.CopyRenderer.Tint = visual.Source.Tint;
			visual.CopyRenderer.RenderType = ModelRenderer.ShadowRenderType.On;
		}

		if ( item.Root.IsValid() && _weaponObject.IsValid() )
		{
			_weaponObject.WorldPosition = item.Root.WorldPosition;
			_weaponObject.WorldRotation = item.Root.WorldRotation;
		}
	}

	void UpdateCustomAnimatedVisual( HeldItem item )
	{
		if ( !_customVisualRoot.IsValid() )
			return;

		HideStockAnimationDriver();

		if ( TryGetOneHandCustomVisualPose( item, out var oneHandPosition, out var oneHandRotation ) )
		{
			_customVisualRoot.WorldPosition = oneHandPosition;
			_customVisualRoot.WorldRotation = oneHandRotation;
			_customVisualRoot.WorldScale = item.CustomViewmodelScale;
			SetCustomVisualRenderType( ModelRenderer.ShadowRenderType.On );
			return;
		}

		if ( !TryGetCustomAnimatedVisualAnchor( item, out var anchor ) )
		{
			SetCustomVisualRenderType( ModelRenderer.ShadowRenderType.Off );
			return;
		}

		var rot = anchor.Rotation * item.CustomViewmodelRotation.ToRotation();
		var position = TryGetCustomHandAnchoredPose( item, rot, item.CustomViewmodelScale, out var handAnchoredPosition )
			? handAnchoredPosition
			: anchor.Position;
		var offset = item.CustomViewmodelOffset;
		_customVisualRoot.WorldPosition = position
			+ rot.Forward * offset.x
			+ rot.Right * offset.y
			+ rot.Up * offset.z;
		_customVisualRoot.WorldRotation = rot;
		_customVisualRoot.WorldScale = item.CustomViewmodelScale;

		SetCustomVisualRenderType( ModelRenderer.ShadowRenderType.On );
	}

	bool TryGetOneHandCustomVisualPose( HeldItem item, out Vector3 position, out Rotation rotation )
	{
		position = default;
		rotation = default;

		if ( item.TwoHanded )
			return false;

		if ( !TryGetStockWeaponAnchor( out var oneHandWeaponAnchor ) )
			return false;

		var handTarget = item.RightHandTarget.IsValid() ? item.RightHandTarget : item.LeftHandTarget;
		if ( !handTarget.IsValid() )
			return false;

		var rightHand = handTarget == item.RightHandTarget;
		if ( !TryGetStockHandAnchor( rightHand, out var oneHandGripAnchor ) )
			return false;

		rotation = oneHandWeaponAnchor.Rotation * item.CustomViewmodelRotation.ToRotation();
		position = oneHandGripAnchor.Position - LocalPointToWorldOffset( handTarget.LocalPosition, rotation, item.CustomViewmodelScale );
		return true;
	}

	bool TryGetCustomHandAnchoredPose( HeldItem item, Rotation rotation, Vector3 scale, out Vector3 position )
	{
		position = default;

		if ( !item.TwoHanded )
		{
			if ( item.RightHandTarget.IsValid() && TryGetStockHandAnchor( true, out var oneHandRightHand ) )
			{
				position = oneHandRightHand.Position - LocalPointToWorldOffset( item.RightHandTarget.LocalPosition, rotation, scale );
				return true;
			}

			if ( item.LeftHandTarget.IsValid() && TryGetStockHandAnchor( false, out var oneHandLeftHand ) )
			{
				position = oneHandLeftHand.Position - LocalPointToWorldOffset( item.LeftHandTarget.LocalPosition, rotation, scale );
				return true;
			}
		}

		var total = Vector3.Zero;
		var count = 0;

		if ( item.RightHandTarget.IsValid() && TryGetStockHandAnchor( true, out var stockRightHand ) )
		{
			total += stockRightHand.Position - LocalPointToWorldOffset( item.RightHandTarget.LocalPosition, rotation, scale );
			count++;
		}

		if ( item.LeftHandTarget.IsValid() && TryGetStockHandAnchor( false, out var stockLeftHand ) )
		{
			total += stockLeftHand.Position - LocalPointToWorldOffset( item.LeftHandTarget.LocalPosition, rotation, scale );
			count++;
		}

		if ( count <= 0 )
			return false;

		position = total / count;
		return true;
	}

	bool TryGetStockHandAnchor( bool rightHand, out Transform transform )
	{
		transform = default;
		if ( !_weaponRenderer.IsValid() )
			return false;

		var names = rightHand
			? new[] { "ValveBiped.Bip01_R_Hand", "hand_R", "right_hand", "R_Hand", "bip01_r_hand" }
			: new[] { "ValveBiped.Bip01_L_Hand", "hand_L", "left_hand", "L_Hand", "bip01_l_hand" };

		foreach ( var boneName in names )
		{
			if ( _weaponRenderer.TryGetBoneTransform( boneName, out transform ) )
				return true;
		}

		return false;
	}

	static Vector3 LocalPointToWorldOffset( Vector3 localPoint, Rotation rotation, Vector3 scale )
	{
		return rotation.Forward * (localPoint.x * scale.x)
			+ rotation.Right * (localPoint.y * scale.y)
			+ rotation.Up * (localPoint.z * scale.z);
	}

	bool TryGetCustomAnimatedVisualAnchor( HeldItem item, out Transform transform )
	{
		if ( TryGetStockWeaponAnchor( out transform ) )
			return true;

		if ( item.Root.IsValid() )
		{
			transform = new Transform( item.Root.WorldPosition, item.Root.WorldRotation, item.Root.WorldScale );
			return true;
		}

		if ( item.RightHandTarget.IsValid() )
		{
			transform = new Transform( item.RightHandTarget.WorldPosition, item.RightHandTarget.WorldRotation, item.RightHandTarget.WorldScale );
			return true;
		}

		if ( item.LeftHandTarget.IsValid() )
		{
			transform = new Transform( item.LeftHandTarget.WorldPosition, item.LeftHandTarget.WorldRotation, item.LeftHandTarget.WorldScale );
			return true;
		}

		transform = default;
		return false;
	}

	void SetCustomVisualRenderType( ModelRenderer.ShadowRenderType renderType )
	{
		foreach ( var visual in _staticVisuals )
		{
			if ( visual.CopyRenderer.IsValid() )
				visual.CopyRenderer.RenderType = renderType;
		}
	}

	bool TryGetStockWeaponAnchor( out Transform transform )
	{
		transform = default;
		if ( !_weaponRenderer.IsValid() )
			return false;

		foreach ( var attachmentName in new[] { "weapon", "Weapon", "root", "muzzle", "Muzzle", "muzzle_flash", "barrel" } )
		{
			var attachment = _weaponRenderer.GetAttachment( attachmentName, true );
			if ( attachment.HasValue )
			{
				transform = attachment.Value;
				return true;
			}
		}

		foreach ( var boneName in new[] { "weapon", "v_weapon", "root", "ValveBiped.Bip01_R_Hand", "hand_R", "right_hand" } )
		{
			if ( _weaponRenderer.TryGetBoneTransform( boneName, out transform ) )
				return true;
		}

		return false;
	}

	void UpdateArmsForStaticFallback( HeldItem item )
	{
		if ( _renderMode != ViewmodelRenderMode.StaticFallback || !_armsRenderer.IsValid() )
			return;

		GetStaticArmsAnchor( item, out var targetPos, out var targetRot );
		var k = 1f - MathF.Exp( -StaticArmFollowRate * Time.Delta );

		_armsObject.WorldPosition = _armsObject.WorldPosition.LengthSquared < 0.01f
			? targetPos
			: Vector3.Lerp( _armsObject.WorldPosition, targetPos, k );
		_armsObject.WorldRotation = Rotation.Slerp( _armsObject.WorldRotation, targetRot, k );

		ApplyHandIk( "hand_L", item.LeftHandTarget );
		ApplyHandIk( "hand_R", item.RightHandTarget );
		ApplyHandIk( "left_hand", item.LeftHandTarget );
		ApplyHandIk( "right_hand", item.RightHandTarget );
	}

	void GetStaticArmsAnchor( HeldItem item, out Vector3 position, out Rotation rotation )
	{
		var hasLeft = item.LeftHandTarget.IsValid();
		var hasRight = item.RightHandTarget.IsValid();

		if ( hasLeft && hasRight )
		{
			position = (item.LeftHandTarget.WorldPosition + item.RightHandTarget.WorldPosition) * 0.5f;
			rotation = Rotation.Slerp( item.LeftHandTarget.WorldRotation, item.RightHandTarget.WorldRotation, 0.5f );
			return;
		}

		if ( hasRight )
		{
			position = item.RightHandTarget.WorldPosition;
			rotation = item.RightHandTarget.WorldRotation;
			return;
		}

		if ( hasLeft )
		{
			position = item.LeftHandTarget.WorldPosition;
			rotation = item.LeftHandTarget.WorldRotation;
			return;
		}

		var validVisual = _staticVisuals.FirstOrDefault( x => x.Source.IsValid() );
		if ( validVisual.Source.IsValid() )
		{
			position = validVisual.Source.GameObject.WorldPosition;
			rotation = validVisual.Source.GameObject.WorldRotation;
			return;
		}

		var fallback = item.Root.IsValid() ? item.Root : GameObject;
		position = fallback.WorldPosition;
		rotation = fallback.WorldRotation;
	}

	void ApplyHandIk( string name, GameObject target )
	{
		if ( !_armsRenderer.IsValid() || !target.IsValid() )
			return;

		_armsRenderer.SetIk( name, new Transform( target.WorldPosition, target.WorldRotation ) );
	}

	void UpdateStockAnimParameters( GroundPlayerController pc, HeldItem item )
	{
		if ( _renderMode == ViewmodelRenderMode.StaticFallback || !_weaponRenderer.IsValid() )
			return;

		var grounded = pc.Components.Get<CharacterController>()?.IsOnGround ?? true;
		var move = item.MoveInput;
		var moving = MathF.Abs( move.x ) > 0.05f || MathF.Abs( move.y ) > 0.05f || MathF.Abs( move.z ) > 0.05f;

		_weaponRenderer.Parameters.Set( "b_grounded", grounded );
		_weaponRenderer.Parameters.Set( "b_sprint", pc.IsSprinting && moving );
		_weaponRenderer.Parameters.Set( "move_bob", moving ? 1f : 0f );
		_weaponRenderer.Parameters.Set( "move_x", move.x.Clamp( -1f, 1f ) );
		_weaponRenderer.Parameters.Set( "move_y", move.y.Clamp( -1f, 1f ) );
		_weaponRenderer.Parameters.Set( "move_z", move.z.Clamp( -1f, 1f ) );
		_weaponRenderer.Parameters.Set( "ironsights", item.IsAds ? 1 : 0 );
		_weaponRenderer.Parameters.Set( "ironsights_fire_scale", item.IsAds ? 0.25f : 1f );
		_weaponRenderer.Parameters.Set( "b_empty", item.IsEmpty );
		_weaponRenderer.Parameters.Set( "attack_hold", item.AttackDown ? 1f : MathF.Max( 0f, 1f - (float)_timeSinceLastAttack * 8f ) );

		if ( item.AttackPressed )
		{
			_weaponRenderer.Parameters.Set( item.IsEmpty ? "b_attack_dry" : "b_attack", true );
			_timeSinceLastAttack = 0f;
		}

		if ( item.ReloadPressed || (item.IsReloading && !_wasReloading) )
			_weaponRenderer.Parameters.Set( "b_reload", true );
		else if ( !item.IsReloading )
			_weaponRenderer.Parameters.Set( "b_reload", false );

		_wasReloading = item.IsReloading;
	}

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

			item = new HeldItem
			{
				Owner = deployer,
				Root = deployer.GameObject,
				HiddenStaticVisualRoot = deployer.DroneInFlight ? deployer.RightHandVisual : null,
				LeftHandTarget = deployer.LeftHandIkTarget,
				RightHandTarget = deployer.DroneInFlight ? deployer.LeftHandIkTarget : deployer.RightHandIkTarget,
				Key = $"deployer:{deployer.GameObject.Id}:{chosenDrone}:{deployer.DroneInFlight}",
				RenderMode = ViewmodelRenderMode.StaticFallback,
				TwoHanded = true,
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

	void DestroyViewmodel()
	{
		_staticVisuals.Clear();
		_weaponRenderer = null;
		_armsRenderer = null;
		_weaponObject = null;
		_customVisualRoot = null;
		_armsObject = null;
		_activeKey = "";
		_renderMode = ViewmodelRenderMode.StaticFallback;
		_wasReloading = false;

		if ( _root.IsValid() )
			_root.Destroy();

		_root = null;
	}
}
