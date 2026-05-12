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
	[Property] public Vector3 RightHandFpOffset { get; set; } = new( 26f, 6f, -10f );
	[Property] public Angles RightHandFpRotation { get; set; } = new( 0f, 0f, 0f );

	[Property] public Vector3 LeftHandTpLocalPos { get; set; } = new( 20f, 0f, 47f );
	[Property] public Angles LeftHandTpLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 RightHandTpLocalPos { get; set; } = new( 22f, 14f, 49f );
	[Property] public Angles RightHandTpLocalAngles { get; set; } = new( 0f, 0f, 0f );

	[Property, Range( 1f, 30f )] public float SwayLerpRate { get; set; } = 18f;

	[Sync] public float LaunchReadyAt { get; set; }
	[Sync] public bool DroneInFlight { get; set; }

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );
	public bool CanLaunch => IsSelected && !DroneInFlight && Time.Now >= LaunchReadyAt;
	public float CooldownRemaining => MathF.Max( 0f, LaunchReadyAt - Time.Now );

	protected override void OnUpdate()
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		var remote = Components.GetInAncestors<RemoteController>();
		var droneViewActive = remote.IsValid() && !remote.IsProxy && remote.DroneViewActive;

		WeaponPose.SetVisibility( GameObject, LeftHandVisual, IsSelected );
		WeaponPose.SetVisibility( GameObject, RightHandVisual, IsSelected && !DroneInFlight && !droneViewActive );

		UpdateHandVisual( LeftHandVisual, pc, droneViewActive, LeftHandFpOffset, LeftHandFpRotation, LeftHandTpLocalPos, LeftHandTpLocalAngles );
		UpdateHandVisual( RightHandVisual, pc, droneViewActive, RightHandFpOffset, RightHandFpRotation, RightHandTpLocalPos, RightHandTpLocalAngles );
		UpdateCitizenHands( pc, droneViewActive );

		if ( CanMutateState() )
			UpdateDroneAliveState();

		if ( !IsProxy && IsSelected && Input.Pressed( "Attack1" ) )
		{
			if ( remote.IsValid() && remote.DroneViewActive )
				return;

			if ( CanLaunch )
				RequestLaunch();
			else if ( DroneInFlight )
				EnterDroneView( remote );
		}
	}

	void UpdateHandVisual( GameObject visual, GroundPlayerController pc, bool forceThirdPerson,
		Vector3 fpOffset, Angles fpRot, Vector3 tpPos, Angles tpRot )
	{
		if ( !visual.IsValid() ) return;

		var firstPersonMode = !forceThirdPerson && !IsProxy && pc.IsValid() && pc.FirstPerson && pc.Eye.IsValid();

		if ( !firstPersonMode )
		{
			visual.LocalPosition = tpPos;
			visual.LocalRotation = tpRot.ToRotation();
			return;
		}

		var look = pc.EyeAngles.ToRotation();
		var targetPos = pc.Eye.WorldPosition
			+ look.Forward * fpOffset.x
			+ look.Right * fpOffset.y
			+ look.Up * fpOffset.z;
		var targetRot = look * fpRot.ToRotation();

		var current = visual.WorldPosition;
		if ( current.LengthSquared < 0.01f )
		{
			visual.WorldPosition = targetPos;
			visual.WorldRotation = targetRot;
		}
		else
		{
			var k = 1f - MathF.Exp( -SwayLerpRate * Time.Delta );
			visual.WorldPosition = Vector3.Lerp( current, targetPos, k );
			visual.WorldRotation = Rotation.Slerp( visual.WorldRotation, targetRot, k );
		}
	}

	void UpdateCitizenHands( GroundPlayerController pc, bool droneViewActive )
	{
		var helper = pc.IsValid() ? pc.AnimationHelper : null;
		if ( !helper.IsValid() ) return;

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
		var droneStillAlive = false;
		if ( pilot.LinkedDroneId != default )
		{
			droneStillAlive = Scene.GetAllComponents<DroneBase>()
				.Any( d => d.GameObject.Id == pilot.LinkedDroneId );
		}

		if ( droneStillAlive ) return;

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
