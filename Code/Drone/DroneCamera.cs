using Sandbox;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Drives the scene camera while a Pilot owns this drone. Mounts the camera
/// to a gimbal-style anchor so it follows yaw but pitch is independent of
/// the physics body (matches a real drone gimbal).
/// </summary>
[Title( "Drone Camera" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "videocam" )]
public sealed class DroneCamera : Component
{
	[Property] public DroneController Drone { get; set; }
	[Property] public GameObject CameraSocket { get; set; }
	[Property] public bool FirstPerson { get; set; } = true;
	[Property] public string CameraToggleInput { get; set; } = "ToggleDroneCamera";
	[Property] public float ChaseDistance { get; set; } = 220f;
	[Property] public float ChaseHeight { get; set; } = 80f;

	/// <summary>
	/// Current local camera mode after runtime toggles are applied.
	/// </summary>
	public bool IsFirstPersonActive => _firstPersonActive;

	bool _firstPersonActive;

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		_firstPersonActive = FirstPerson;
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();

		if ( IsProxy )
		{
			SetPilotVisualHidden( false );
			return;
		}

		if ( !Drone.IsValid() )
		{
			SetPilotVisualHidden( false );
			return;
		}

		// When the local pilot has toggled OUT of drone view (or there's no
		// pilot yet), don't drive the scene camera — let GroundPlayerController
		// keep first-person view on the ground avatar. The drone hovers in
		// place because DroneController is gated on the same condition.
		if ( !RemoteController.IsLocalDroneViewActive( Scene ) )
		{
			SetPilotVisualHidden( false );
			return;
		}

		if ( !string.IsNullOrWhiteSpace( CameraToggleInput ) && Input.Pressed( CameraToggleInput ) )
			_firstPersonActive = !_firstPersonActive;

		var cam = Scene.GetAllComponents<CameraComponent>().FirstOrDefault();
		if ( !cam.IsValid() )
		{
			SetPilotVisualHidden( false );
			return;
		}

		var lookRot = Drone.EyeAngles.ToRotation();
		var firstPersonActive = _firstPersonActive && CameraSocket.IsValid();
		SetPilotVisualHidden( firstPersonActive );

		if ( firstPersonActive )
		{
			cam.WorldPosition = CameraSocket.WorldPosition;
			cam.WorldRotation = lookRot;
		}
		else
		{
			var chaseRot = Rotation.From( 0, Drone.EyeAngles.yaw, 0 );
			cam.WorldPosition = Drone.WorldPosition + chaseRot.Backward * ChaseDistance + Vector3.Up * ChaseHeight;
			cam.WorldRotation = lookRot;
		}
	}

	protected override void OnDestroy()
	{
		SetPilotVisualHidden( false );
	}

	void ResolvePrefabReferences()
	{
		if ( !Drone.IsValid() )
			Drone = Components.Get<DroneController>();

		if ( !CameraSocket.IsValid() )
			CameraSocket = GameObject.Children.FirstOrDefault( x => x.Name == "CameraSocket" );
	}

	void SetPilotVisualHidden( bool hidden )
	{
		var visualModel = Drone.IsValid() && Drone.VisualModel.IsValid()
			? Drone.VisualModel
			: GameObject.Children.FirstOrDefault( x => x.Name == "Visual" );

		if ( !visualModel.IsValid() ) return;

		var renderType = hidden
			? ModelRenderer.ShadowRenderType.ShadowsOnly
			: ModelRenderer.ShadowRenderType.On;

		foreach ( var renderer in visualModel.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
		{
			renderer.RenderType = renderType;
		}
	}
}
