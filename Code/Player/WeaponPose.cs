using Sandbox;
using System;

namespace DroneVsPlayers;

/// <summary>
/// Shared helpers for "held item" components (weapons + thrown equipment) so
/// the M4, shotgun, drone jammer, and grenades all use the exact same FPS
/// viewmodel pose, third-person fallback, slot-selection check, ADS lerping,
/// view-inertia smoothing, and hide-when-stowed behaviour.
///
/// Each consumer adds a <c>Slot</c> property plus hip/ADS viewmodel offset
/// properties and calls the viewmodel update helpers plus the visibility helpers
/// every frame in <c>OnUpdate</c>.
/// </summary>
public static class WeaponPose
{
	/// <summary>
	/// True if this item's slot is the currently selected loadout slot, or if
	/// there's no <see cref="SoldierLoadout"/> in the ancestor chain (so the
	/// item is always "active" in editor playtests without a soldier).
	/// </summary>
	public static bool IsSlotSelected( Component owner, int slot )
	{
		if ( owner is null ) return true;
		var loadout = FindLoadout( owner );
		return !loadout.IsValid() || loadout.ActiveSlot == slot;
	}

	static SoldierLoadout FindLoadout( Component owner )
	{
		var loadout = owner.Components.GetInAncestors<SoldierLoadout>();
		if ( loadout.IsValid() )
			return loadout;

		var current = owner.GameObject;
		while ( current.IsValid() )
		{
			loadout = current.Components.Get<SoldierLoadout>();
			if ( loadout.IsValid() )
				return loadout;

			current = current.Parent;
		}

		return null;
	}

	/// <summary>
	/// Positions the held item's GameObject every frame. For the local player
	/// in first person, blends between hip (FirstPersonOffset) and ADS
	/// (AdsOffset) by the controller's current <c>AdsT</c> factor, and lerps
	/// toward the target each frame for view-inertia / sway feel. For
	/// everyone else (and for third-person view) it falls back to the
	/// body-local pose so remote players see the weapon at the soldier's
	/// chest.
	/// </summary>
	public static void UpdateViewmodel(
		Component owner,
		bool isProxy,
		Vector3 firstPersonOffset,
		Angles firstPersonRotationOffset,
		Vector3 adsOffset,
		Angles adsRotationOffset,
		Vector3 thirdPersonLocalPosition,
		Angles thirdPersonLocalAngles,
		float swayLerpRate = 18f )
	{
		if ( owner is null ) return;
		var pc = owner.Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var go = owner.GameObject;

		if ( !isProxy && pc.FirstPerson && pc.Eye.IsValid() )
		{
			var look = pc.EyeAngles.ToRotation();
			var adsT = pc.AdsT;

			// Hip ↔ ADS blend on the per-axis offset, and a slerp for rotation.
			var blendedOffset = Vector3.Lerp( firstPersonOffset, adsOffset, adsT );
			var blendedRot = Rotation.Slerp(
				firstPersonRotationOffset.ToRotation(),
				adsRotationOffset.ToRotation(),
				adsT );

			var targetPos = pc.Eye.WorldPosition
				+ look.Forward * blendedOffset.x
				+ look.Right * blendedOffset.y
				+ look.Up * blendedOffset.z;
			var targetRot = look * blendedRot;

			// View-inertia smoothing: lerp displayed pose toward target.
			// First-frame initialisation: if the GameObject is at the world
			// origin (just spawned), snap to target.
			var current = go.WorldPosition;
			if ( current.LengthSquared < 0.01f )
			{
				go.WorldPosition = targetPos;
				go.WorldRotation = targetRot;
			}
			else
			{
				var k = 1f - MathF.Exp( -swayLerpRate * Time.Delta );
				go.WorldPosition = Vector3.Lerp( current, targetPos, k );
				go.WorldRotation = Rotation.Slerp( go.WorldRotation, targetRot, k );
			}
			return;
		}

		go.LocalPosition = thirdPersonLocalPosition;
		go.LocalRotation = thirdPersonLocalAngles.ToRotation();
	}

	/// <summary>
	/// Backwards-compatible overload — no ADS offsets supplied, so hip is
	/// used regardless of <c>pc.AdsT</c>. Used by held items that don't
	/// support aim-down-sights (e.g. thrown grenades).
	/// </summary>
	public static void UpdateViewmodel(
		Component owner,
		bool isProxy,
		Vector3 firstPersonOffset,
		Angles firstPersonRotationOffset,
		Vector3 thirdPersonLocalPosition,
		Angles thirdPersonLocalAngles )
	{
		UpdateViewmodel( owner, isProxy,
			firstPersonOffset, firstPersonRotationOffset,
			firstPersonOffset, firstPersonRotationOffset,
			thirdPersonLocalPosition, thirdPersonLocalAngles );
	}

	/// <summary>
	/// Hides the held item without removing it from the scene. Renderers are
	/// turned fully off while hidden so stowed equipment cannot cast shadows.
	/// </summary>
	public static void SetVisibility( GameObject root, bool visible )
	{
		SetVisibility( root, null, visible );
	}

	/// <summary>
	/// Hides one visual subtree without removing it from the scene.
	/// </summary>
	public static void SetVisibility( GameObject root, GameObject visualOverride, bool visible )
	{
		var renderRoot = visualOverride.IsValid() ? visualOverride : root;
		if ( !renderRoot.IsValid() ) return;

		var renderType = visible
			? ModelRenderer.ShadowRenderType.On
			: ModelRenderer.ShadowRenderType.Off;

		foreach ( var renderer in renderRoot.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			renderer.RenderType = renderType;

		foreach ( var renderer in renderRoot.Components.GetAll<SkinnedModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			renderer.RenderType = renderType;
	}
}
