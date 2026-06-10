using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

// Viewmodel construction and teardown: builds the stock/custom/static rigs, loads models, owns DestroyViewmodel.
public sealed partial class FirstPersonViewmodel
{
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
		// Spawn per-bone GameObjects so the visible custom model can be parented
		// to the stock weapon's grip bone and ride the exact same skeleton the
		// bone-merged arms use — that is what keeps the gun glued to the hands
		// while turning instead of lagging a frame behind them.
		_weaponRenderer.CreateBoneObjects = true;
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

		var copyObject = parent;
		var copyRenderer = copyObject.Components.Get<ModelRenderer>();
		if ( !copyRenderer.IsValid() )
		{
			copyObject = new GameObject( parent, true, "WeaponVisual" )
			{
				NetworkMode = NetworkMode.Never
			};
			copyRenderer = copyObject.Components.Create<ModelRenderer>();
		}

		copyObject.NetworkMode = NetworkMode.Never;
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
		_customVisualBoneAttached = false;
		_customVisualPoseFrames = 0;
		_customVisualScale = Vector3.One;

		if ( _root.IsValid() )
			_root.Destroy();

		_root = null;
	}
}
