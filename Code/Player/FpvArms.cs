using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// First-person arms viewmodel. Sits as a child of the soldier's Eye and
/// renders a stylised forearm/glove model that follows the camera each
/// frame. Only the local owner sees their own arms — for everyone else
/// the renderer is hidden (the third-person citizen body already has
/// proper limbs).
///
/// Position blends from <see cref="HipOffset"/> to <see cref="AdsOffset"/>
/// using <see cref="GroundPlayerController.AdsT"/> so the arms pull in
/// tight when aiming down sights, same as held weapons. View-inertia
/// smoothing matches <see cref="WeaponPose"/> so the arms drift slightly
/// behind the camera on snappy mouse flicks.
/// </summary>
[Title( "FPV Arms" )]
[Category( "Drone vs Players/Player" )]
[Icon( "back_hand" )]
public sealed class FpvArms : Component
{
	[Property] public ModelRenderer ArmsRenderer { get; set; }

	[Property] public Vector3 HipOffset { get; set; } = new Vector3( 0f, -2f, -4f );
	[Property] public Angles HipRotationOffset { get; set; } = new Angles( 0f, 0f, 0f );

	[Property] public Vector3 AdsOffset { get; set; } = new Vector3( -6f, -2f, 2f );
	[Property] public Angles AdsRotationOffset { get; set; } = new Angles( 0f, 0f, 0f );

	[Property, Range( 1f, 40f )] public float SwayLerpRate { get; set; } = 18f;

	protected override void OnStart()
	{
		if ( !ArmsRenderer.IsValid() )
			ArmsRenderer = Components.Get<ModelRenderer>( FindMode.EverythingInSelfAndDescendants );
	}

	protected override void OnUpdate()
	{
		if ( !ArmsRenderer.IsValid() )
			ArmsRenderer = Components.Get<ModelRenderer>( FindMode.EverythingInSelfAndDescendants );

		var pc = Components.GetInAncestors<GroundPlayerController>();
		var remote = Components.GetInAncestors<RemoteController>();
		var droneViewActive = remote.IsValid() && !remote.IsProxy && remote.DroneViewActive;
		bool shouldShow = pc.IsValid() && pc.Enabled && !IsProxy && pc.FirstPerson && pc.Eye.IsValid() && !droneViewActive;

		SetVisible( shouldShow );

		if ( !shouldShow || !pc.IsValid() ) return;

		var look = pc.EyeAngles.ToRotation();
		var adsT = pc.AdsT;

		var blendedOffset = Vector3.Lerp( HipOffset, AdsOffset, adsT );
		var blendedRot = Rotation.Slerp(
			HipRotationOffset.ToRotation(),
			AdsRotationOffset.ToRotation(),
			adsT );

		var targetPos = pc.Eye.WorldPosition
			+ look.Forward * blendedOffset.x
			+ look.Right * blendedOffset.y
			+ look.Up * blendedOffset.z;
		var targetRot = look * blendedRot;

		var current = WorldPosition;
		if ( current.LengthSquared < 0.01f )
		{
			WorldPosition = targetPos;
			WorldRotation = targetRot;
		}
		else
		{
			var k = 1f - MathF.Exp( -SwayLerpRate * Time.Delta );
			WorldPosition = Vector3.Lerp( current, targetPos, k );
			WorldRotation = Rotation.Slerp( WorldRotation, targetRot, k );
		}
	}

	void SetVisible( bool visible )
	{
		if ( !ArmsRenderer.IsValid() ) return;
		ArmsRenderer.RenderType = visible
			? ModelRenderer.ShadowRenderType.On
			: ModelRenderer.ShadowRenderType.Off;
	}
}
