using Sandbox;
using System;
using System.Collections.Generic;

namespace DroneVsPlayers;

/// <summary>
/// Authoring volume for climbable ladders. Put this on the same GameObject as
/// a BoxCollider; the collider is kept as a trigger and the player controller
/// uses the box bounds as the climb volume.
/// </summary>
[Title( "Ladder Volume" )]
[Category( "Drone vs Players/Environment" )]
[Icon( "stairs" )]
public sealed class LadderVolume : Component
{
	static readonly List<LadderVolume> ActiveVolumes = new();

	[Property] public bool AutoConfigureCollider { get; set; } = true;
	[Property, Range( 0f, 64f )] public float GrabPadding { get; set; } = 18f;
	[Property] public bool UseTopExit { get; set; } = true;
	[Property] public Vector3 TopExitLocalOffset { get; set; } = new( 0f, 60f, 272f );
	[Property, Range( 0f, 80f )] public float TopExitTriggerDistance { get; set; } = 28f;
	[Property, Range( 0f, 80f )] public float BottomExitTriggerDistance { get; set; } = 8f;

	/// <summary>
	/// Find the closest active ladder volume intersecting the player's
	/// character-controller bounds.
	/// </summary>
	public static LadderVolume FindForPlayer( GroundPlayerController player, CharacterController controller )
	{
		if ( !player.IsValid() || !controller.IsValid() )
			return null;

		var radius = MathF.Max( 1f, controller.Radius );
		var height = MathF.Max( 1f, controller.Height );
		var playerBounds = new BBox(
			player.WorldPosition + new Vector3( -radius, -radius, 0f ),
			player.WorldPosition + new Vector3( radius, radius, height ) );

		LadderVolume best = null;
		var bestDistance = float.MaxValue;

		for ( var i = ActiveVolumes.Count - 1; i >= 0; i-- )
		{
			var volume = ActiveVolumes[i];
			if ( !volume.IsValid() )
			{
				ActiveVolumes.RemoveAt( i );
				continue;
			}

			if ( !volume.Active )
				continue;

			var bounds = volume.GetClimbBounds();
			if ( !bounds.Overlaps( playerBounds ) )
				continue;

			var distance = (bounds.Center - player.WorldPosition).WithZ( 0f ).LengthSquared;
			if ( distance >= bestDistance )
				continue;

			bestDistance = distance;
			best = volume;
		}

		return best;
	}

	/// <summary>
	/// Get the world-space climb bounds used by player movement.
	/// </summary>
	public BBox GetClimbBounds()
	{
		var collider = Components.Get<BoxCollider>();
		if ( collider.IsValid() )
			return collider.GetWorldBounds().Grow( GrabPadding );

		return GameObject.GetBounds().Grow( GrabPadding );
	}

	/// <summary>
	/// Get the world-space position where a player should dismount at the top.
	/// </summary>
	public Vector3 GetTopExitWorldPosition()
	{
		return WorldTransform.PointToWorld( TopExitLocalOffset );
	}

	protected override void OnEnabled()
	{
		base.OnEnabled();
		if ( !ActiveVolumes.Contains( this ) )
			ActiveVolumes.Add( this );

		ConfigureCollider();
	}

	protected override void OnDisabled()
	{
		base.OnDisabled();
		ActiveVolumes.Remove( this );
	}

	protected override void OnDestroy()
	{
		base.OnDestroy();
		ActiveVolumes.Remove( this );
	}

	protected override void OnStart()
	{
		base.OnStart();
		ConfigureCollider();
	}

	protected override void OnValidate()
	{
		base.OnValidate();
		ConfigureCollider();
	}

	void ConfigureCollider()
	{
		if ( !AutoConfigureCollider )
			return;

		var collider = Components.Get<BoxCollider>();
		if ( !collider.IsValid() )
			return;

		collider.Static = true;
		collider.IsTrigger = true;
	}
}
