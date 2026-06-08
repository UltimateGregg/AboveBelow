using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Pilot's slot-1 held item. Shows a mini-drone in the right hand and an RC
/// transmitter in the left while selected. Left-click clones the chosen drone
/// variant at the held position and gives it initial forward velocity; once
/// airborne, a second left-click or F enters drone view.
///
/// One drone in flight per pilot. When the linked drone is destroyed, a
/// cooldown begins; once expired, the mini-drone reappears in hand and LMB
/// can launch again.
/// </summary>
[Title( "Drone Deployer" )]
[Category( "Drone vs Players/Player" )]
[Icon( "settings_remote" )]
public sealed class DroneDeployer : Component
{
	const string HeldPropellerPrefabPath = "prefabs/items/held_drone_propeller.prefab";

	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	[Property] public GameObject LeftHandVisual { get; set; }
	[Property] public GameObject RightHandVisual { get; set; }
	[Property] public GameObject LeftHandIkTarget { get; set; }
	[Property] public GameObject RightHandIkTarget { get; set; }

	[Property] public GameObject GpsDronePrefab { get; set; }
	[Property] public GameObject FpvDronePrefab { get; set; }
	[Property] public GameObject FiberOpticFpvDronePrefab { get; set; }
	[Property] public GameSetup Setup { get; set; }

	[Property] public float LaunchCooldown { get; set; } = 8f;
	[Property] public float LaunchSpeed { get; set; } = 300f;
	/// <summary>Eye-space offset where the drone clone appears at launch (fwd, right, up).</summary>
	[Property] public Vector3 LaunchSpawnOffset { get; set; } = new( 60f, 0f, -4f );

	[Property] public Vector3 LeftHandFpOffset { get; set; } = new( 30f, -18f, -12f );
	[Property] public Angles LeftHandFpRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 LeftHandIkFpOffset { get; set; } = new( 8f, -14f, 2f );
	[Property] public Angles LeftHandIkFpRotation { get; set; } = new( 60f, -10f, 0f );
	[Property] public Vector3 RightHandFpOffset { get; set; } = new( 36f, -5f, -20f );
	[Property] public Angles RightHandFpRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Angles GpsHeldDroneFpRotationOffset { get; set; } = new( 0f, -90f, 0f );
	[Property] public Vector3 RightHandIkFpOffset { get; set; } = new( 37f, 13f, -4f );
	[Property] public Angles RightHandIkFpRotation { get; set; } = new( 10f, 0f, 170f );
	[Property] public Vector3 RightHandControllerIkFpOffset { get; set; } = new( -1.5f, -5f, 1f );
	[Property] public Angles RightHandControllerIkFpRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public bool UseVisualRelativeFirstPersonIkTargets { get; set; } = true;
	[Property] public bool UsePilotBodyHands { get; set; } = true;

	[Property] public Vector3 LeftHandTpLocalPos { get; set; } = new( 20f, 0f, 47f );
	[Property] public Angles LeftHandTpLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 LeftHandIkTpLocalPos { get; set; } = new( 28f, -8f, 44f );
	[Property] public Angles LeftHandIkTpLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 RightHandTpLocalPos { get; set; } = new( 22f, 14f, 49f );
	[Property] public Angles RightHandTpLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 RightHandIkTpLocalPos { get; set; } = new( 34f, 10f, 46f );
	[Property] public Angles RightHandIkTpLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 RightHandControllerIkTpLocalPos { get; set; } = new( 24f, 4f, 44f );
	[Property] public Angles RightHandControllerIkTpLocalAngles { get; set; } = new( 0f, 0f, 0f );

	[Property] public string GpsHeldDroneModelPath { get; set; } = "models/drone_high.vmdl";
	[Property] public string FpvHeldDroneModelPath { get; set; } = "models/drone_fpv.vmdl";
	[Property] public string FiberHeldDroneModelPath { get; set; } = "models/drone_fpv_fiber.vmdl";
	[Property] public string GpsHeldPropellerModelPath { get; set; } = "models/drone_gps_prop.vmdl";
	[Property] public string FpvHeldPropellerModelPath { get; set; } = "models/drone_fpv_prop.vmdl";
	[Property] public Vector3 GpsHeldDroneScale { get; set; } = new( 0.075f, 0.075f, 0.075f );
	[Property] public Vector3 FpvHeldDroneScale { get; set; } = new( 0.3f, 0.3f, 0.3f );
	[Property] public Vector3 FiberHeldDroneScale { get; set; } = new( 0.3f, 0.3f, 0.3f );
	[Property] public Color GpsHeldDroneTint { get; set; } = Color.White;
	[Property] public Color FpvHeldDroneTint { get; set; } = Color.White;
	[Property] public Color FiberHeldDroneTint { get; set; } = Color.White;
	[Property] public CitizenAnimationHelper.HoldTypes PilotHandHoldType { get; set; } = CitizenAnimationHelper.HoldTypes.HoldItem;

	[Property, Range( 1f, 30f )] public float SwayLerpRate { get; set; } = 18f;

	[Sync] public float LaunchReadyAt { get; set; }
	[Sync] public bool DroneInFlight { get; set; }

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool CanLaunch => IsSelected && !HasActiveDrone() && Time.Now >= LaunchReadyAt;
	public float CooldownRemaining => MathF.Max( 0f, LaunchReadyAt - Time.Now );

	string _activeHeldDroneModelPath = "";
	string _activeHeldPropellerModelPath = "";
	string _warnedHeldPropellerModelPath = "";
	Model _activeHeldPropellerModel;

	static readonly HeldPropellerVisualSpec[] GpsHeldPropellers =
	{
		new( "HeldPropeller_FL", new Vector3( 58.36f, 86.4f, 6.6f ), new Angles( 0f, 0f, 0f ), new Vector3( 4f, 4f, 4f ) ),
		new( "HeldPropeller_FR", new Vector3( 58.36f, -86.4f, 6.6f ), new Angles( 0f, 180f, 0f ), new Vector3( 4f, 4f, 4f ) ),
		new( "HeldPropeller_BL", new Vector3( -58.36f, 86.4f, 6.6f ), new Angles( 0f, 180f, 0f ), new Vector3( 4f, 4f, 4f ) ),
		new( "HeldPropeller_BR", new Vector3( -58.36f, -86.4f, 6.6f ), new Angles( 0f, 0f, 0f ), new Vector3( 4f, 4f, 4f ) ),
	};

	static readonly HeldPropellerVisualSpec[] FpvHeldPropellers =
	{
		new( "HeldPropeller_FL", new Vector3( 6.71f, 6.71f, 1.8f ), new Angles( 0f, 0f, 0f ) ),
		new( "HeldPropeller_FR", new Vector3( 6.71f, -6.71f, 1.8f ), new Angles( 0f, 180f, 0f ) ),
		new( "HeldPropeller_BL", new Vector3( -6.71f, 6.71f, 1.8f ), new Angles( 0f, 180f, 0f ) ),
		new( "HeldPropeller_BR", new Vector3( -6.71f, -6.71f, 1.8f ), new Angles( 0f, 0f, 0f ) ),
	};

	readonly struct HeldPropellerVisualSpec
	{
		public readonly string Name;
		public readonly Vector3 LocalPosition;
		public readonly Angles LocalRotation;
		public readonly Vector3 LocalScale;

		public HeldPropellerVisualSpec( string name, Vector3 localPosition, Angles localRotation )
			: this( name, localPosition, localRotation, Vector3.One )
		{
		}

		public HeldPropellerVisualSpec( string name, Vector3 localPosition, Angles localRotation, Vector3 localScale )
		{
			Name = name;
			LocalPosition = localPosition;
			LocalRotation = localRotation;
			LocalScale = localScale;
		}
	}

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		ResolveSetup();
		UpdateChosenDroneVisual();
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();
		ResolveSetup();
		UpdateChosenDroneVisual();

		var pc = Components.GetInAncestors<GroundPlayerController>();
		var remote = Components.GetInAncestors<RemoteController>();
		var droneViewActive = remote.IsValid() && !remote.IsProxy && remote.DroneViewActive;
		var chosenDrone = GetChosenDrone();

		var selected = ApplySelectionVisualState( droneViewActive );

		if ( selected )
		{
			UpdateHandVisual(
				LeftHandVisual,
				LeftHandIkTarget,
				pc,
				droneViewActive,
				LeftHandFpOffset,
				LeftHandFpRotation,
				LeftHandIkFpOffset,
				LeftHandIkFpRotation,
				LeftHandTpLocalPos,
				LeftHandTpLocalAngles,
				LeftHandIkTpLocalPos,
				LeftHandIkTpLocalAngles,
				LeftHandVisual );

			UpdateHandVisual(
				RightHandVisual,
				RightHandIkTarget,
				pc,
				droneViewActive,
				RightHandFpOffset,
				GetHeldDroneFpRotation( chosenDrone ),
				DroneInFlight ? RightHandControllerIkFpOffset : RightHandIkFpOffset,
				DroneInFlight ? RightHandControllerIkFpRotation : RightHandIkFpRotation,
				RightHandTpLocalPos,
				RightHandTpLocalAngles,
				DroneInFlight ? RightHandControllerIkTpLocalPos : RightHandIkTpLocalPos,
				DroneInFlight ? RightHandControllerIkTpLocalAngles : RightHandIkTpLocalAngles,
				DroneInFlight ? LeftHandVisual : RightHandVisual );
		}
		UpdateCitizenHands( pc, droneViewActive );

		if ( CanMutateState() )
			UpdateDroneAliveState();

		if ( !IsProxy && IsSelected && !LocalOptionsState.ConsumesGameplayInput && Input.Pressed( "Attack1" ) )
		{
			if ( remote.IsValid() && remote.DroneViewActive )
				return;

			var hasActiveDrone = HasActiveDrone();
			if ( CanLaunch )
				RequestLaunch();
			else if ( DroneInFlight || hasActiveDrone )
				EnterDroneView( remote );
		}
	}

	internal bool ApplySelectionVisualState()
	{
		return ApplySelectionVisualState( IsDroneViewActive() );
	}

	bool ApplySelectionVisualState( bool droneViewActive )
	{
		var selected = IsSelected;
		WeaponPose.SetVisibility( GameObject, false );

		if ( !selected || droneViewActive )
			return false;

		var hideForFirstPersonViewmodel = FirstPersonViewmodel.ShouldHideWorldHeldItem( this, selected );
		WeaponPose.SetVisibility( LeftHandVisual, !hideForFirstPersonViewmodel );
		WeaponPose.SetVisibility( RightHandVisual, !hideForFirstPersonViewmodel && !DroneInFlight );
		return true;
	}

	bool IsDroneViewActive()
	{
		var remote = Components.GetInAncestors<RemoteController>();
		return remote.IsValid() && remote.DroneViewActive;
	}

	void ResolvePrefabReferences()
	{
		if ( !LeftHandVisual.IsValid() )
			LeftHandVisual = GameObject.Children.FirstOrDefault( x => x.Name == "LeftHand" );
		if ( !RightHandVisual.IsValid() )
			RightHandVisual = GameObject.Children.FirstOrDefault( x => x.Name == "RightHand" );
		if ( !LeftHandIkTarget.IsValid() )
			LeftHandIkTarget = GameObject.Children.FirstOrDefault( x => x.Name == "LeftHandIk" );
		if ( !RightHandIkTarget.IsValid() )
			RightHandIkTarget = GameObject.Children.FirstOrDefault( x => x.Name == "RightHandIk" );
	}

	void ResolveSetup()
	{
		if ( Setup.IsValid() )
			return;

		Setup = Scene.GetAllComponents<GameSetup>().FirstOrDefault();
	}

	void UpdateChosenDroneVisual()
	{
		if ( !RightHandVisual.IsValid() )
			return;

		var renderer = RightHandVisual.Components.Get<ModelRenderer>();
		if ( !renderer.IsValid() )
			return;

		var chosenDrone = GetChosenDrone();

		var modelPath = ResolveHeldDroneModelPath( chosenDrone );

		if ( !string.IsNullOrWhiteSpace( modelPath ) && _activeHeldDroneModelPath != modelPath )
		{
			var model = Model.Load( modelPath );
			if ( model is not null && model.IsValid )
			{
				renderer.Model = model;
				_activeHeldDroneModelPath = modelPath;
			}
			else
			{
				Log.Warning( $"[DroneDeployer] Could not load held drone model '{modelPath}' for {chosenDrone}" );
			}
		}

		RightHandVisual.LocalScale = chosenDrone switch
		{
			DroneType.Gps => GpsHeldDroneScale,
			DroneType.Fpv => FpvHeldDroneScale,
			DroneType.FiberOpticFpv => FiberHeldDroneScale,
			_ => FpvHeldDroneScale
		};

		renderer.Tint = chosenDrone switch
		{
			DroneType.Gps => GpsHeldDroneTint,
			DroneType.Fpv => FpvHeldDroneTint,
			DroneType.FiberOpticFpv => FiberHeldDroneTint,
			_ => FpvHeldDroneTint
		};

		UpdateHeldPropellerVisuals( chosenDrone );
	}

	DroneType GetChosenDrone()
	{
		var pilot = Components.GetInAncestors<PilotSoldier>();
		return pilot.IsValid() ? pilot.ChosenDrone : DroneType.Fpv;
	}

	Angles GetHeldDroneFpRotation( DroneType chosenDrone )
	{
		if ( chosenDrone == DroneType.Gps )
			return new Angles(
				RightHandFpRotation.pitch + GpsHeldDroneFpRotationOffset.pitch,
				RightHandFpRotation.yaw + GpsHeldDroneFpRotationOffset.yaw,
				RightHandFpRotation.roll + GpsHeldDroneFpRotationOffset.roll );

		return RightHandFpRotation;
	}

	void EnsureHeldPropellerVisuals( HeldPropellerVisualSpec[] specs )
	{
		if ( !RightHandVisual.IsValid() )
			return;

		foreach ( var spec in specs )
		{
			var propeller = RightHandVisual.Children.FirstOrDefault( child => child.Name == spec.Name );
			if ( !propeller.IsValid() )
				propeller = CreateHeldPropellerVisual( spec.Name );

			propeller.LocalPosition = spec.LocalPosition;
			propeller.LocalRotation = spec.LocalRotation.ToRotation();
			propeller.LocalScale = spec.LocalScale;

			if ( !propeller.Components.Get<ModelRenderer>().IsValid() )
				propeller.Components.Create<ModelRenderer>();
		}
	}

	GameObject CreateHeldPropellerVisual( string name )
	{
		var prefab = GameObject.GetPrefab( HeldPropellerPrefabPath );
		if ( prefab.IsValid() )
		{
			var clone = prefab.Clone( new Transform( Vector3.Zero, Rotation.Identity ), RightHandVisual, true, name );
			if ( clone.IsValid() )
			{
				clone.NetworkMode = NetworkMode.Never;
				return clone;
			}
		}

		return new GameObject( RightHandVisual, true, name )
		{
			NetworkMode = NetworkMode.Never
		};
	}

	void UpdateHeldPropellerVisuals( DroneType chosenDrone )
	{
		var specs = chosenDrone == DroneType.Gps ? GpsHeldPropellers : FpvHeldPropellers;
		EnsureHeldPropellerVisuals( specs );

		var showPropellers = chosenDrone is DroneType.Gps or DroneType.Fpv or DroneType.FiberOpticFpv;
		var propellerModel = showPropellers ? LoadHeldPropellerModel( chosenDrone ) : null;

		foreach ( var spec in specs )
		{
			var propeller = RightHandVisual.IsValid()
				? RightHandVisual.Children.FirstOrDefault( child => child.Name == spec.Name )
				: null;
			if ( !propeller.IsValid() )
				continue;

			var renderer = propeller.Components.Get<ModelRenderer>();
			if ( !renderer.IsValid() )
				continue;

			if ( !showPropellers || propellerModel is null || !propellerModel.IsValid )
			{
				renderer.Model = null;
				renderer.RenderType = ModelRenderer.ShadowRenderType.Off;
				continue;
			}

			renderer.Model = propellerModel;
			renderer.Tint = Color.White;
			renderer.RenderType = ModelRenderer.ShadowRenderType.On;
		}
	}

	Model LoadHeldPropellerModel( DroneType chosenDrone )
	{
		var modelPath = chosenDrone switch
		{
			DroneType.Gps => GpsHeldPropellerModelPath,
			DroneType.Fpv => FpvHeldPropellerModelPath,
			DroneType.FiberOpticFpv => FpvHeldPropellerModelPath,
			_ => FpvHeldPropellerModelPath
		};

		if ( string.IsNullOrWhiteSpace( modelPath ) )
			return null;

		if ( _activeHeldPropellerModelPath == modelPath
			&& _activeHeldPropellerModel is not null
			&& _activeHeldPropellerModel.IsValid )
		{
			return _activeHeldPropellerModel;
		}

		var model = Model.Load( modelPath );
		if ( model is not null && model.IsValid )
		{
			_activeHeldPropellerModel = model;
			_activeHeldPropellerModelPath = modelPath;
			return model;
		}

		if ( _warnedHeldPropellerModelPath != modelPath )
		{
			Log.Warning( $"[DroneDeployer] Could not load held drone propeller model '{modelPath}'" );
			_warnedHeldPropellerModelPath = modelPath;
		}

		return null;
	}

	string ResolveHeldDroneModelPath( DroneType chosenDrone )
	{
		var definition = Setup.IsValid()
			? Setup.GetAuthoredDroneLoadoutDefinition( chosenDrone )
			: null;

		if ( definition is not null )
		{
			if ( !string.IsNullOrWhiteSpace( definition.HeldModelPath ) )
				return definition.HeldModelPath;

			if ( !string.IsNullOrWhiteSpace( definition.PreviewModelPath ) )
				return definition.PreviewModelPath;
		}

		return chosenDrone switch
		{
			DroneType.Gps => GpsHeldDroneModelPath,
			DroneType.Fpv => FpvHeldDroneModelPath,
			DroneType.FiberOpticFpv => FiberHeldDroneModelPath,
			_ => FpvHeldDroneModelPath
		};
	}

	void UpdateHandVisual( GameObject visual, GameObject ikTarget, GroundPlayerController pc, bool forceThirdPerson,
		Vector3 visualFpOffset, Angles visualFpRot, Vector3 ikFpOffset, Angles ikFpRot,
		Vector3 visualTpPos, Angles visualTpRot, Vector3 ikTpPos, Angles ikTpRot, GameObject ikAnchorVisual )
	{
		if ( !visual.IsValid() && !ikTarget.IsValid() ) return;

		var firstPersonMode = !forceThirdPerson && !IsProxy && pc.IsValid() && pc.FirstPerson && pc.Eye.IsValid();

		if ( !firstPersonMode )
		{
			ApplyLocalPose( visual, visualTpPos, visualTpRot.ToRotation() );
			ApplyLocalPose( ikTarget, ikTpPos, ikTpRot.ToRotation() );
			return;
		}

		var look = pc.EyeAngles.ToRotation();
		var visualPos = EyeOffsetToWorld( pc, look, visualFpOffset );
		var visualRot = look * visualFpRot.ToRotation();

		ApplySmoothedWorldPose( visual, visualPos, visualRot );

		var firstPersonIkAnchor = ikAnchorVisual.IsValid() ? ikAnchorVisual : visual;
		if ( UseVisualRelativeFirstPersonIkTargets && firstPersonIkAnchor.IsValid() )
		{
			var ikPos = firstPersonIkAnchor.WorldTransform.PointToWorld( ikFpOffset );
			var ikRot = firstPersonIkAnchor.WorldTransform.RotationToWorld( ikFpRot.ToRotation() );
			ApplyWorldPose( ikTarget, ikPos, ikRot );
			return;
		}

		ApplySmoothedWorldPose(
			ikTarget,
			EyeOffsetToWorld( pc, look, ikFpOffset ),
			look * ikFpRot.ToRotation() );
	}

	static Vector3 EyeOffsetToWorld( GroundPlayerController pc, Rotation look, Vector3 offset )
	{
		return pc.Eye.WorldPosition
			+ look.Forward * offset.x
			+ look.Right * offset.y
			+ look.Up * offset.z;
	}

	void ApplySmoothedWorldPose( GameObject go, Vector3 targetPos, Rotation targetRot )
	{
		if ( !go.IsValid() ) return;

		var current = go.WorldPosition;
		if ( current.LengthSquared < 0.01f )
		{
			ApplyWorldPose( go, targetPos, targetRot );
		}
		else
		{
			var k = 1f - MathF.Exp( -SwayLerpRate * Time.Delta );
			var displayPos = Vector3.Lerp( current, targetPos, k );
			var displayRot = Rotation.Slerp( go.WorldRotation, targetRot, k );
			ApplyWorldPose( go, displayPos, displayRot );
		}
	}

	static void ApplyLocalPose( GameObject go, Vector3 position, Rotation rotation )
	{
		if ( !go.IsValid() ) return;
		go.LocalPosition = position;
		go.LocalRotation = rotation;
	}

	static void ApplyWorldPose( GameObject go, Vector3 position, Rotation rotation )
	{
		if ( !go.IsValid() ) return;
		go.WorldPosition = position;
		go.WorldRotation = rotation;
	}

	void UpdateCitizenHands( GroundPlayerController pc, bool droneViewActive )
	{
		var helper = pc.IsValid() ? pc.AnimationHelper : null;
		if ( !helper.IsValid() ) return;

		if ( FirstPersonViewmodel.ShouldHideWorldHeldItem( this, IsSelected ) )
		{
			if ( helper.IkLeftHand == LeftHandIkTarget || helper.IkLeftHand == LeftHandVisual )
				helper.IkLeftHand = null;
			if ( helper.IkRightHand == RightHandIkTarget || helper.IkRightHand == RightHandVisual )
				helper.IkRightHand = null;
			return;
		}

		var leftTarget = LeftHandIkTarget.IsValid() ? LeftHandIkTarget : LeftHandVisual;
		var rightTarget = RightHandIkTarget.IsValid() ? RightHandIkTarget : RightHandVisual;

		if ( IsSelected )
		{
			helper.HoldType = PilotHandHoldType;
			helper.Handedness = CitizenAnimationHelper.Hand.Both;
			helper.IkLeftHand = leftTarget;
			helper.IkRightHand = rightTarget;
			return;
		}

		if ( helper.IkLeftHand == leftTarget )
			helper.IkLeftHand = null;
		if ( helper.IkRightHand == rightTarget )
			helper.IkRightHand = null;
	}

	void UpdateDroneAliveState()
	{
		var pilot = Components.GetInAncestors<PilotSoldier>();
		if ( !pilot.IsValid() ) return;

		if ( !DroneInFlight && pilot.ResolveDrone().IsValid() )
			DroneInFlight = true;

		var activeDrone = ResolveActiveDrone( pilot );
		if ( activeDrone.IsValid() )
		{
			DroneInFlight = true;
			pilot.LinkedDroneId = activeDrone.GameObject.Id;
			return;
		}

		if ( !DroneInFlight ) return;

		DroneInFlight = false;
		LaunchReadyAt = Time.Now + LaunchCooldown;
		pilot.LinkedDroneId = default;
	}

	bool HasActiveDrone()
	{
		var pilot = Components.GetInAncestors<PilotSoldier>();
		return ResolveActiveDrone( pilot ).IsValid();
	}

	DroneBase ResolveActiveDrone( PilotSoldier pilot )
	{
		if ( !pilot.IsValid() )
			return null;

		var linkedDrone = pilot.ResolveDrone();
		if ( linkedDrone.IsValid() )
			return linkedDrone;

		var ownerId = pilot.GameObject.Network.Owner?.Id ?? GameObject.Network.Owner?.Id ?? default;
		if ( ownerId == default )
			return null;

		return Scene.GetAllComponents<PilotLink>()
			.Where( link => link.IsValid() && link.PilotId == ownerId )
			.Select( link => link.DroneBase.IsValid()
				? link.DroneBase
				: link.Components.Get<DroneBase>( FindMode.EverythingInSelfAndDescendants ) )
			.FirstOrDefault( IsActiveDrone );
	}

	static bool IsActiveDrone( DroneBase drone )
	{
		if ( !drone.IsValid() ) return false;

		var health = drone.Components.Get<Health>() ?? drone.Components.GetInAncestors<Health>();
		return health.IsValid() && !health.IsDead;
	}

	void RequestLaunch()
	{
		if ( HasActiveDrone() )
		{
			DroneInFlight = true;
			return;
		}

		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() || !pc.Eye.IsValid() ) return;

		var look = pc.EyeAngles.ToRotation();
		var spawnPos = pc.Eye.WorldPosition
			+ look.Forward * LaunchSpawnOffset.x
			+ look.Right * LaunchSpawnOffset.y
			+ look.Up * LaunchSpawnOffset.z;
		var spawnRot = Rotation.FromYaw( pc.EyeAngles.yaw );
		var velocity = look.Forward * LaunchSpeed;

		var ownerId = GameObject.Network.Owner?.Id ?? default;
		ServerLaunchDrone( ownerId, spawnPos, spawnRot, velocity );
	}

#if DEBUG
	internal void DebugLaunchDroneForProbe( Guid pilotConnectionId, Vector3 position, Rotation rotation, Vector3 velocity )
	{
		ServerLaunchDrone( pilotConnectionId, position, rotation, velocity );
	}
#endif

	void EnterDroneView( RemoteController remote )
	{
		if ( !remote.IsValid() ) return;
		if ( !remote.HasLinkedDrone() ) return;

		remote.SetDroneViewActive( true );
	}

	[Rpc.Host]
	void ServerLaunchDrone( Guid pilotConnectionId, Vector3 position, Rotation rotation, Vector3 velocity )
	{
		if ( !CanMutateState() ) return;

		var pilot = Components.GetInAncestors<PilotSoldier>();
		if ( !pilot.IsValid() ) return;

		if ( DroneInFlight || pilot.ResolveDrone().IsValid() )
		{
			var linkedDrone = ResolveActiveDrone( pilot );
			if ( linkedDrone.IsValid() )
				pilot.LinkedDroneId = linkedDrone.GameObject.Id;
			DroneInFlight = true;
			return;
		}

		var activeDrone = ResolveActiveDrone( pilot );
		if ( activeDrone.IsValid() )
		{
			pilot.LinkedDroneId = activeDrone.GameObject.Id;
			DroneInFlight = true;
			return;
		}

		var prefab = ResolveLaunchPrefab( pilot.ChosenDrone );

		if ( !prefab.IsValid() )
		{
			Log.Warning( $"[DroneDeployer] No prefab assigned for variant {pilot.ChosenDrone}" );
			return;
		}

		var clone = prefab.Clone( new Transform( position, rotation ),
			name: $"Drone[{pilot.ChosenDrone}] - {pilot.GameObject.Name}" );
		BalanceApplier.ApplyDrone( clone, pilot.ChosenDrone, GetActiveBalanceConfig() );

		var link = clone.Components.Get<PilotLink>( FindMode.EverythingInSelfAndDescendants );
		if ( link.IsValid() )
			link.PilotId = pilotConnectionId;

		var body = clone.Components.Get<Rigidbody>( FindMode.EverythingInSelfAndDescendants );
		if ( body.IsValid() )
			body.Velocity = velocity;

		var droneController = clone.Components.Get<DroneController>( FindMode.EverythingInSelfAndDescendants );
		if ( droneController.IsValid() )
		{
			var ee = droneController.EyeAngles;
			ee.yaw = rotation.Yaw();
			droneController.EyeAngles = ee;
		}

		if ( Networking.IsActive )
		{
			var conn = Connection.All.FirstOrDefault( c => c.Id == pilotConnectionId );
			if ( conn is not null )
				clone.NetworkSpawn( conn );
			else
				clone.NetworkSpawn();
		}

		pilot.LinkedDroneId = clone.Id;
		DroneInFlight = true;
	}

	GameObject ResolveLaunchPrefab( DroneType chosenDrone )
	{
		ResolveSetup();

		var definition = Setup.IsValid()
			? Setup.GetAuthoredDroneLoadoutDefinition( chosenDrone )
			: null;

		if ( definition is not null && !string.IsNullOrWhiteSpace( definition.PrefabPath ) )
		{
			var resourcePrefab = GameObject.GetPrefab( definition.PrefabPath );
			if ( resourcePrefab.IsValid() )
				return resourcePrefab;
		}

		return chosenDrone switch
		{
			DroneType.Gps => GpsDronePrefab,
			DroneType.Fpv => FpvDronePrefab,
			DroneType.FiberOpticFpv => FiberOpticFpvDronePrefab,
			_ => FpvDronePrefab,
		};
	}

	BalanceConfigResource GetActiveBalanceConfig()
	{
		ResolveSetup();

		return Setup.IsValid() && Setup.Rules.IsValid()
			? Setup.Rules.GetActiveBalanceConfig()
			: null;
	}

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;
}
