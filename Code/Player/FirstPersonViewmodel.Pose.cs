using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

// Per-frame pose updates: root follow, custom-visual anchoring/bone attach, static arms IK, stock anim parameters.
public sealed partial class FirstPersonViewmodel
{
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

		// Once attached, the custom visual is a child of the stock weapon's grip
		// bone, so the engine moves it in lockstep with the bone-merged arms. We
		// only keep the scale pinned (in case the bone carries a non-unit scale)
		// and never touch its world position/rotation again — that is what stops
		// the gun drifting away from the hands during fast camera turns.
		if ( _customVisualBoneAttached )
		{
			_customVisualRoot.WorldScale = _customVisualScale;
			SetCustomVisualRenderType( ModelRenderer.ShadowRenderType.On );
			return;
		}

		if ( !TryComputeCustomVisualWorldPose( item, out var position, out var rotation, out var scale ) )
		{
			SetCustomVisualRenderType( ModelRenderer.ShadowRenderType.Off );
			return;
		}

		_customVisualScale = scale;
		_customVisualRoot.WorldPosition = position;
		_customVisualRoot.WorldRotation = rotation;
		_customVisualRoot.WorldScale = scale;
		SetCustomVisualRenderType( ModelRenderer.ShadowRenderType.On );

		// Let the stock idle settle for a couple of frames, then lock the visible
		// custom weapon onto the stock skeleton's grip bone for good.
		_customVisualPoseFrames++;
		if ( _customVisualPoseFrames >= 2 )
			TryAttachCustomVisualToStockSkeleton();
	}

	/// <summary>
	/// Solves the world pose the visible custom weapon should sit at relative to
	/// the hidden stock animation driver's hand/weapon bones. Used to seed the
	/// pose before the visual is parented onto the stock grip bone.
	/// </summary>
	bool TryComputeCustomVisualWorldPose( HeldItem item, out Vector3 position, out Rotation rotation, out Vector3 scale )
	{
		position = default;
		rotation = Rotation.Identity;
		scale = item.CustomViewmodelScale;

		if ( TryGetOneHandCustomVisualPose( item, out var oneHandPosition, out var oneHandRotation ) )
		{
			position = oneHandPosition;
			rotation = oneHandRotation;
			return true;
		}

		if ( !TryGetCustomAnimatedVisualAnchor( item, out var anchor ) )
			return false;

		rotation = anchor.Rotation * item.CustomViewmodelRotation.ToRotation();
		var basePosition = TryGetCustomHandAnchoredPose( item, rotation, item.CustomViewmodelScale, out var handAnchoredPosition )
			? handAnchoredPosition
			: anchor.Position;
		var offset = item.CustomViewmodelOffset;
		position = basePosition
			+ rotation.Forward * offset.x
			+ rotation.Right * offset.y
			+ rotation.Up * offset.z;
		return true;
	}

	/// <summary>
	/// Parents the visible custom weapon onto the stock animation driver's grip
	/// bone so it can never desync from the bone-merged arms. Falls back silently
	/// (keeps per-frame positioning) if the bone GameObjects are not ready yet.
	/// </summary>
	void TryAttachCustomVisualToStockSkeleton()
	{
		if ( _customVisualBoneAttached || !_customVisualRoot.IsValid() )
			return;

		var boneObject = FindStockWeaponBoneObject();
		if ( !boneObject.IsValid() )
			return;

		// keepWorldPosition: true preserves the pose we just solved, then the
		// custom visual follows the bone from here on.
		_customVisualRoot.SetParent( boneObject, true );
		_customVisualBoneAttached = true;
	}

	GameObject FindStockWeaponBoneObject()
	{
		if ( !_weaponRenderer.IsValid() )
			return null;

		foreach ( var boneName in new[] { "weapon", "v_weapon", "hold", "hold_R", "hand_R", "ValveBiped.Bip01_R_Hand", "right_hand" } )
		{
			var bone = _weaponRenderer.GetBoneObject( boneName );
			if ( bone.IsValid() )
				return bone;
		}

		return null;
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
		// Pilot deployer: anchor the arms near the camera so the forearms read as
		// proper first-person arms rising into view, and let the hands IK out to
		// the controller/drone grip targets instead of floating at their midpoint.
		if ( item.UseEyeArmsAnchor )
		{
			var pc = Components.Get<GroundPlayerController>();
			if ( pc.IsValid() && pc.Eye.IsValid() )
			{
				var eyeRot = pc.Eye.WorldRotation;
				position = pc.Eye.WorldPosition
					+ eyeRot.Forward * item.ArmsEyeOffset.x
					+ eyeRot.Right * item.ArmsEyeOffset.y
					+ eyeRot.Up * item.ArmsEyeOffset.z;
				rotation = eyeRot;
				return;
			}
		}

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
}
