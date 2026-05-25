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
	[Property] public int Slot { get; set; } = SoldierLoadout.PrimarySlot;

	[Property] public GameObject LeftHandVisual { get; set; }
	[Property] public GameObject RightHandVisual { get; set; }
	[Property] public GameObject LeftHandIkTarget { get; set; }
	[Property] public GameObject RightHandIkTarget { get; set; }

	[Property] public GameObject GpsDronePrefab { get; set; }
	[Property] public GameObject FpvDronePrefab { get; set; }
	[Property] public GameObject FiberOpticFpvDronePrefab { get; set; }

	[Property] public float LaunchCooldown { get; set; } = 8f;
	[Property] public float LaunchSpeed { get; set; } = 300f;
	/// <summary>Eye-space offset where the drone clone appears at launch (fwd, right, up).</summary>
	[Property] public Vector3 LaunchSpawnOffset { get; set; } = new( 60f, 0f, -4f );

	[Property] public Vector3 LeftHandFpOffset { get; set; } = new( 28f, -6f, -10f );
	[Property] public Angles LeftHandFpRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 LeftHandIkFpOffset { get; set; } = new( 28f, -10f, -12f );
	[Property] public Angles LeftHandIkFpRotation { get; set; } = new( 0f, 180f, 0f );
	[Property] public Vector3 RightHandFpOffset { get; set; } = new( 26f, 6f, -10f );
	[Property] public Angles RightHandFpRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 RightHandIkFpOffset { get; set; } = new( 32f, 10f, -10f );
	[Property] public Angles RightHandIkFpRotation { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 RightHandControllerIkFpOffset { get; set; } = new( 29f, -2f, -12f );
	[Property] public Angles RightHandControllerIkFpRotation { get; set; } = new( 0f, 180f, 0f );

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
	[Property] public string FpvHeldPropellerModelPath { get; set; } = "models/drone_fpv_prop.vmdl";
	[Property] public Vector3 GpsHeldDroneScale { get; set; } = new( 0.075f, 0.075f, 0.075f );
	[Property] public Vector3 FpvHeldDroneScale { get; set; } = new( 0.3f, 0.3f, 0.3f );
	[Property] public Vector3 FiberHeldDroneScale { get; set; } = new( 0.3f, 0.3f, 0.3f );
	[Property] public Color GpsHeldDroneTint { get; set; } = Color.White;
	[Property] public Color FpvHeldDroneTint { get; set; } = Color.White;
	[Property] public Color FiberHeldDroneTint { get; set; } = Color.White;

	[Property, Range( 1f, 30f )] public float SwayLerpRate { get; set; } = 18f;

	[Sync] public float LaunchReadyAt { get; set; }
	[Sync] public bool DroneInFlight { get; set; }

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool CanLaunch => IsSelected && !DroneInFlight && Time.Now >= LaunchReadyAt;
	public float CooldownRemaining => MathF.Max( 0f, LaunchReadyAt - Time.Now );

	string _activeHeldDroneModelPath = "";
	string _activeHeldPropellerModelPath = "";
	string _warnedHeldPropellerModelPath = "";
	Model _activeHeldPropellerModel;

	static readonly HeldPropellerVisualSpec[] HeldPropellers =
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

		public HeldPropellerVisualSpec( string name, Vector3 localPosition, Angles localRotation )
		{
			Name = name;
			LocalPosition = localPosition;
			LocalRotation = localRotation;
		}
	}

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		UpdateChosenDroneVisual();
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();
		UpdateChosenDroneVisual();

		var pc = Components.GetInAncestors<GroundPlayerController>();
		var remote = Components.GetInAncestors<RemoteController>();
		var droneViewActive = remote.IsValid() && !remote.IsProxy && remote.DroneViewActive;

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
				LeftHandIkTpLocalAngles );

			UpdateHandVisual(
				RightHandVisual,
				RightHandIkTarget,
				pc,
				droneViewActive,
				RightHandFpOffset,
				RightHandFpRotation,
				DroneInFlight ? RightHandControllerIkFpOffset : RightHandIkFpOffset,
				DroneInFlight ? RightHandControllerIkFpRotation : RightHandIkFpRotation,
				RightHandTpLocalPos,
				RightHandTpLocalAngles,
				DroneInFlight ? RightHandControllerIkTpLocalPos : RightHandIkTpLocalPos,
				DroneInFlight ? RightHandControllerIkTpLocalAngles : RightHandIkTpLocalAngles );
		}
		UpdateCitizenHands( pc, droneViewActive );

		if ( CanMutateState() )
			UpdateDroneAliveState();

		if ( !IsProxy && IsSelected && !LocalOptionsState.ConsumesGameplayInput && Input.Pressed( "Attack1" ) )
		{
			if ( remote.IsValid() && remote.DroneViewActive )
				return;

			if ( CanLaunch )
				RequestLaunch();
			else if ( DroneInFlight )
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

	void UpdateChosenDroneVisual()
	{
		if ( !RightHandVisual.IsValid() )
			return;

		var renderer = RightHandVisual.Components.Get<ModelRenderer>();
		if ( !renderer.IsValid() )
			return;

		var pilot = Components.GetInAncestors<PilotSoldier>();
		var chosenDrone = pilot.IsValid() ? pilot.ChosenDrone : DroneType.Fpv;

		var modelPath = chosenDrone switch
		{
			DroneType.Gps => GpsHeldDroneModelPath,
			DroneType.Fpv => FpvHeldDroneModelPath,
			DroneType.FiberOpticFpv => FiberHeldDroneModelPath,
			_ => FpvHeldDroneModelPath
		};

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

	void EnsureHeldPropellerVisuals()
	{
		if ( !RightHandVisual.IsValid() )
			return;

		foreach ( var spec in HeldPropellers )
		{
			var propeller = RightHandVisual.Children.FirstOrDefault( child => child.Name == spec.Name );
			if ( !propeller.IsValid() )
			{
				propeller = new GameObject( RightHandVisual, true, spec.Name )
				{
					NetworkMode = NetworkMode.Never
				};
			}

			propeller.LocalPosition = spec.LocalPosition;
			propeller.LocalRotation = spec.LocalRotation.ToRotation();
			propeller.LocalScale = Vector3.One;

			if ( !propeller.Components.Get<ModelRenderer>().IsValid() )
				propeller.Components.Create<ModelRenderer>();
		}
	}

	void UpdateHeldPropellerVisuals( DroneType chosenDrone )
	{
		EnsureHeldPropellerVisuals();

		var showPropellers = chosenDrone is DroneType.Fpv or DroneType.FiberOpticFpv;
		var propellerModel = showPropellers ? LoadHeldPropellerModel() : null;

		foreach ( var spec in HeldPropellers )
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

	Model LoadHeldPropellerModel()
	{
		if ( string.IsNullOrWhiteSpace( FpvHeldPropellerModelPath ) )
			return null;

		if ( _activeHeldPropellerModelPath == FpvHeldPropellerModelPath
			&& _activeHeldPropellerModel is not null
			&& _activeHeldPropellerModel.IsValid )
		{
			return _activeHeldPropellerModel;
		}

		var model = Model.Load( FpvHeldPropellerModelPath );
		if ( model is not null && model.IsValid )
		{
			_activeHeldPropellerModel = model;
			_activeHeldPropellerModelPath = FpvHeldPropellerModelPath;
			return model;
		}

		if ( _warnedHeldPropellerModelPath != FpvHeldPropellerModelPath )
		{
			Log.Warning( $"[DroneDeployer] Could not load held drone propeller model '{FpvHeldPropellerModelPath}'" );
			_warnedHeldPropellerModelPath = FpvHeldPropellerModelPath;
		}

		return null;
	}

	void UpdateHandVisual( GameObject visual, GameObject ikTarget, GroundPlayerController pc, bool forceThirdPerson,
		Vector3 visualFpOffset, Angles visualFpRot, Vector3 ikFpOffset, Angles ikFpRot,
		Vector3 visualTpPos, Angles visualTpRot, Vector3 ikTpPos, Angles ikTpRot )
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
		var ikPos = EyeOffsetToWorld( pc, look, ikFpOffset );
		var ikRot = look * ikFpRot.ToRotation();

		ApplySmoothedWorldPose( visual, visualPos, visualRot );
		ApplySmoothedWorldPose( ikTarget, ikPos, ikRot );
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
		var rightTarget = DroneInFlight || droneViewActive
			? (RightHandIkTarget.IsValid() ? RightHandIkTarget : LeftHandVisual)
			: (RightHandVisual.IsValid() ? RightHandVisual : RightHandIkTarget);

		if ( IsSelected )
		{
			helper.HoldType = CitizenAnimationHelper.HoldTypes.HoldItem;
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
		if ( !DroneInFlight ) return;

		var pilot = Components.GetInAncestors<PilotSoldier>();
		if ( !pilot.IsValid() ) return;

		// Drone was never recorded, or has been removed from the scene.
		if ( pilot.ResolveDrone().IsValid() ) return;

		DroneInFlight = false;
		LaunchReadyAt = Time.Now + LaunchCooldown;
		pilot.LinkedDroneId = default;
	}

	void RequestLaunch()
	{
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

	void EnterDroneView( RemoteController remote )
	{
		if ( !remote.IsValid() ) return;
		if ( !remote.HasLinkedDrone() ) return;

		remote.SetDroneViewActive( true );
	}

	[Rpc.Broadcast]
	void ServerLaunchDrone( Guid pilotConnectionId, Vector3 position, Rotation rotation, Vector3 velocity )
	{
		if ( !CanMutateState() ) return;
		if ( DroneInFlight ) return;

		var pilot = Components.GetInAncestors<PilotSoldier>();
		if ( !pilot.IsValid() ) return;

		var prefab = pilot.ChosenDrone switch
		{
			DroneType.Gps => GpsDronePrefab,
			DroneType.Fpv => FpvDronePrefab,
			DroneType.FiberOpticFpv => FiberOpticFpvDronePrefab,
			_ => FpvDronePrefab,
		};

		if ( !prefab.IsValid() )
		{
			Log.Warning( $"[DroneDeployer] No prefab assigned for variant {pilot.ChosenDrone}" );
			return;
		}

		var clone = prefab.Clone( new Transform( position, rotation ),
			name: $"Drone[{pilot.ChosenDrone}] - {pilot.GameObject.Name}" );

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

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;
}
