using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Local-only first-person held-item renderer. It spawns a viewmodel weapon or
/// item for the local player, then spawns Facepunch first-person arms on top of
/// that item. Facepunch stock weapon viewmodels are preferred and use the
/// documented arms-to-weapon bonemerge path; custom project items fall back to
/// copied static item visuals plus IK targets sampled from the existing
/// held-item grip points.
/// </summary>
[Title( "First Person Viewmodel" )]
[Category( "Drone vs Players/Player" )]
[Icon( "front_hand" )]
public sealed class FirstPersonViewmodel : Component
{
	[Property] public string ArmsModelPath { get; set; } = "facepunch/v_first_person_arms_human";
	[Property] public string ArmsFallbackModelPath { get; set; } = "models/first_person/first_person_arms_preview.vmdl";

	[Property] public string AssaultRifleViewmodelPath { get; set; } = "facepunch/v_m4a1";
	[Property] public string PilotSmgViewmodelPath { get; set; } = "facepunch/v_mp5";
	[Property] public string ShotgunViewmodelPath { get; set; } = "facepunch/v_spaghellim4";
	[Property] public string FragGrenadeViewmodelPath { get; set; } = "facepunch/v_he_grenade";
	[Property] public string ChaffGrenadeViewmodelPath { get; set; } = "facepunch/v_smoke_grenade";
	[Property] public string EmpGrenadeViewmodelPath { get; set; } = "facepunch/v_decoy_grenade";

	[Property] public Vector3 StockViewmodelOffset { get; set; } = Vector3.Zero;
	[Property] public Angles StockViewmodelRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property, Range( 1f, 60f )] public float StaticArmFollowRate { get; set; } = 28f;

	GameObject _root;
	GameObject _weaponObject;
	GameObject _armsObject;
	SkinnedModelRenderer _weaponRenderer;
	SkinnedModelRenderer _armsRenderer;
	string _activeKey = "";
	bool _activeUsesStockViewmodel;
	bool _wasReloading;
	TimeSince _timeSinceLastAttack = 10f;

	readonly List<StaticVisual> _staticVisuals = new();

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
		public GameObject LeftHandTarget;
		public GameObject RightHandTarget;
		public string Key;
		public string StockModelPath;
		public bool HasStockViewmodel;
		public bool TwoHanded;
		public bool IsAds;
		public bool IsReloading;
		public bool IsEmpty;
		public bool AttackPressed;
		public bool AttackDown;
		public bool ReloadPressed;
		public Vector3 MoveInput;
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
		_activeUsesStockViewmodel = item.HasStockViewmodel && BuildStockWeaponViewmodel( item );
		if ( !_activeUsesStockViewmodel )
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

		_weaponObject = new GameObject( _root, true, $"Viewmodel Weapon - {item.Key}" )
		{
			NetworkMode = NetworkMode.Never
		};

		_weaponRenderer = _weaponObject.Components.Create<SkinnedModelRenderer>();
		_weaponRenderer.Model = weaponModel;
		_weaponRenderer.RenderType = ModelRenderer.ShadowRenderType.On;
		_weaponRenderer.UseAnimGraph = true;
		_weaponRenderer.Parameters.Set( "b_deploy_skip", true );
		_weaponRenderer.Parameters.Set( "skeleton", 0 );
		_weaponRenderer.Parameters.Set( "b_twohanded", item.TwoHanded );

		CreateArmsRenderer( _weaponRenderer );
		return true;
	}

	void BuildStaticItemViewmodel( HeldItem item )
	{
		CreateRoot();

		_weaponObject = new GameObject( _root, true, $"Viewmodel Item - {item.Key}" )
		{
			NetworkMode = NetworkMode.Never
		};

		foreach ( var source in item.Root.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
		{
			if ( !source.IsValid() || source.Model is null || !source.Model.IsValid )
				continue;

			var copyObject = new GameObject( _weaponObject, true, source.GameObject.Name )
			{
				NetworkMode = NetworkMode.Never
			};

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
		}

		CreateArmsRenderer( null );
	}

	void CreateRoot()
	{
		_root = new GameObject( true, "Local First Person Viewmodel" )
		{
			NetworkMode = NetworkMode.Never
		};
	}

	void CreateArmsRenderer( SkinnedModelRenderer boneMergeTarget )
	{
		var armsModel = TryLoadModel( ArmsModelPath );
		if ( armsModel is null || !armsModel.IsValid )
			armsModel = TryLoadModel( ArmsFallbackModelPath );

		if ( armsModel is null || !armsModel.IsValid )
			return;

		_armsObject = new GameObject( _root, true, "Viewmodel Arms" )
		{
			NetworkMode = NetworkMode.Never
		};

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
		if ( _activeUsesStockViewmodel )
			return;

		foreach ( var visual in _staticVisuals )
		{
			if ( !visual.Source.IsValid() || !visual.CopyObject.IsValid() || !visual.CopyRenderer.IsValid() )
				continue;

			visual.CopyObject.WorldPosition = visual.Source.GameObject.WorldPosition;
			visual.CopyObject.WorldRotation = visual.Source.GameObject.WorldRotation;
			visual.CopyObject.WorldScale = visual.Source.GameObject.WorldScale;
			visual.CopyRenderer.RenderType = ModelRenderer.ShadowRenderType.On;
		}

		if ( item.Root.IsValid() && _weaponObject.IsValid() )
		{
			_weaponObject.WorldPosition = item.Root.WorldPosition;
			_weaponObject.WorldRotation = item.Root.WorldRotation;
		}
	}

	void UpdateArmsForStaticFallback( HeldItem item )
	{
		if ( _activeUsesStockViewmodel || !_armsRenderer.IsValid() )
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
		if ( !_activeUsesStockViewmodel || !_weaponRenderer.IsValid() )
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

			item = new HeldItem
			{
				Owner = deployer,
				Root = deployer.GameObject,
				LeftHandTarget = deployer.LeftHandIkTarget,
				RightHandTarget = deployer.RightHandIkTarget,
				Key = $"deployer:{deployer.GameObject.Id}",
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
				LeftHandTarget = weapon.LeftHandIkTarget,
				RightHandTarget = weapon.RightHandIkTarget,
				Key = $"hitscan:{weapon.GameObject.Id}:{(isSmg ? "mp5" : "m4a1")}",
				StockModelPath = isSmg ? PilotSmgViewmodelPath : AssaultRifleViewmodelPath,
				HasStockViewmodel = true,
				TwoHanded = !isSmg,
				IsAds = pc.IsAds,
				IsReloading = weapon.IsReloading,
				IsEmpty = weapon.AmmoInMagazine <= 0,
				AttackPressed = Input.Down( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				ReloadPressed = Input.Pressed( "Reload" ),
				MoveInput = moveInput
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
				LeftHandTarget = shotgun.LeftHandIkTarget,
				RightHandTarget = shotgun.RightHandIkTarget,
				Key = $"shotgun:{shotgun.GameObject.Id}",
				StockModelPath = ShotgunViewmodelPath,
				HasStockViewmodel = true,
				TwoHanded = true,
				IsAds = pc.IsAds,
				AttackPressed = Input.Pressed( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				MoveInput = moveInput
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
				LeftHandTarget = jammer.LeftHandIkTarget,
				RightHandTarget = jammer.RightHandIkTarget,
				Key = $"jammer:{jammer.GameObject.Id}",
				TwoHanded = true,
				IsAds = pc.IsAds,
				AttackPressed = Input.Pressed( "Attack1" ),
				AttackDown = Input.Down( "Attack1" ),
				MoveInput = moveInput
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
		if ( _weaponRenderer.IsValid() && _weaponRenderer.Model is not null && _weaponRenderer.Model.IsValid )
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
		_armsObject = null;
		_activeKey = "";
		_activeUsesStockViewmodel = false;
		_wasReloading = false;

		if ( _root.IsValid() )
			_root.Destroy();

		_root = null;
	}
}
