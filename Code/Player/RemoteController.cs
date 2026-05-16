using Sandbox;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Pilot's "weapon slot" item. Toggles the local camera between the pilot's
/// ground POV and the linked drone's DroneCamera. While drone-POV is
/// active, the existing DroneController on the drone reads input as normal
/// (input is ignored on the ground avatar's controller during that time).
///
/// First pass: input is global, so leaving the drone POV simply hands control
/// back to the GroundPlayerController. The drone's input gating is owned by
/// JammingReceiver / PilotLink already.
/// </summary>
[Title( "Remote Controller" )]
[Category( "Drone vs Players/Player" )]
[Icon( "tablet_android" )]
public sealed class RemoteController : Component
{
	[Property] public string ToggleInput { get; set; } = "TogglePilotControl";

	/// <summary>True while the local pilot is viewing through the drone.</summary>
	[Sync] public bool DroneViewActive { get; set; }

	/// <summary>
	/// Static helper for the drone's components (DroneCamera, DroneController) to
	/// check whether the LOCAL player is currently flying — i.e. whether their
	/// RemoteController has DroneViewActive set. If no local pilot exists (e.g.
	/// editor playtest with a manually-placed drone), returns true so the drone
	/// is testable in isolation.
	/// </summary>
	public static bool IsLocalDroneViewActive( Scene scene )
	{
		if ( scene is null ) return true;
		var local = scene.GetAllComponents<RemoteController>().FirstOrDefault( r => !r.IsProxy );
		return !local.IsValid() || local.DroneViewActive;
	}

	public void SetDroneViewActive( bool active )
	{
		if ( IsProxy ) return;
		if ( active && !HasLinkedDrone() ) return;

		DroneViewActive = active;
	}

	public bool HasLinkedDrone()
	{
		ResolveRefs();
		if ( !_pilot.IsValid() || _pilot.LinkedDroneId == default ) return false;

		return _pilot.ResolveDrone().IsValid();
	}

	GroundPlayerController _groundController;
	PilotSoldier _pilot;
	GameObject _body;
	GameObject _eye;

	protected override void OnStart()
	{
		ResolveRefs();
	}

	protected override void OnUpdate()
	{
		if ( IsProxy ) return;

		ResolveRefs();
		if ( !_pilot.IsValid() ) return;

		if ( DroneViewActive && !HasLinkedDrone() )
			SetDroneViewActive( false );

		if ( !LocalOptionsState.ConsumesGameplayInput && Input.Pressed( ToggleInput ) )
			SetDroneViewActive( !DroneViewActive );

		// Remote camera placement: when drone view is active, hide the ground
		// HUD by simply not driving the camera here — DroneCamera on the
		// drone takes over because its OnUpdate runs (drone is not a proxy
		// to its owner). When drone view is off, GroundPlayerController.HandleLook
		// runs and drives the camera back to first person on the avatar.
		// All we do here is gate the local soldier's input so they don't
		// strafe while flying.
		if ( _groundController.IsValid() )
			_groundController.Enabled = !DroneViewActive;

		// While flying the drone, make the ground avatar's body visible to
		// the local player (the pilot wants to see their own body from the
		// drone's POV). GroundPlayerController.HandleLook would otherwise set
		// it to ShadowsOnly for its own first-person rendering, but it's now
		// disabled during drone view, so we must override.
		if ( DroneViewActive )
		{
			SetGroundBodyVisible( true );
			SetEyeViewmodelsVisible( false );
		}
		else
		{
			SetEyeViewmodelsVisible( true );
		}
	}

	void SetGroundBodyVisible( bool visible )
	{
		if ( !_body.IsValid() )
			_body = GameObject.Children.FirstOrDefault( c => c.Name == "Body" );
		if ( !_body.IsValid() ) return;

		var renderType = visible
			? ModelRenderer.ShadowRenderType.On
			: ModelRenderer.ShadowRenderType.ShadowsOnly;

		foreach ( var mr in _body.Components.GetAll<SkinnedModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			mr.RenderType = renderType;
	}

	void SetEyeViewmodelsVisible( bool visible )
	{
		if ( !_eye.IsValid() )
			_eye = GameObject.Children.FirstOrDefault( c => c.Name == "Eye" );
		if ( !_eye.IsValid() ) return;

		var renderType = visible
			? ModelRenderer.ShadowRenderType.On
			: ModelRenderer.ShadowRenderType.Off;

		foreach ( var mr in _eye.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			mr.RenderType = renderType;
	}

	void ResolveRefs()
	{
		if ( !_pilot.IsValid() )
			_pilot = Components.Get<PilotSoldier>();
		if ( !_groundController.IsValid() )
			_groundController = Components.Get<GroundPlayerController>();
		if ( !_body.IsValid() )
			_body = GameObject.Children.FirstOrDefault( c => c.Name == "Body" );
		if ( !_eye.IsValid() )
			_eye = GameObject.Children.FirstOrDefault( c => c.Name == "Eye" );
	}
}
