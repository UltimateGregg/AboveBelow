using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Citizen-bodied target for solo playtesting. Has a Health
/// component so weapons get the full hitmarker / kill-feed / impact-FX
/// loop, but uses none of the player components (so RoundManager's
/// win-condition checks don't count it as a soldier or pilot).
///
/// On death the dummy hides itself, waits <see cref="RespawnSeconds"/>, then
/// resets Health and shows itself again. Drop a few of these in main.scene
/// for target practice.
/// </summary>
[Title( "Training Dummy" )]
[Category( "Drone vs Players" )]
[Icon( "accessibility_new" )]
public sealed class TrainingDummy : Component
{
	[Property, Range( 1f, 30f )] public float RespawnSeconds { get; set; } = 4f;
	[Property, Sync] public PlayerRole TeamRole { get; set; } = PlayerRole.Soldier;
	[Property] public GameObject Body { get; set; }
	[Property] public CitizenAnimationHelper AnimationHelper { get; set; }
	[Property] public Health Health { get; set; }
	[Property] public bool MoveAround { get; set; } = true;
	[Property, Range( 0f, 512f )] public float WanderRadius { get; set; } = 220f;
	[Property, Range( 0f, 240f )] public float MoveSpeed { get; set; } = 75f;
	[Property, Range( 0.25f, 8f )] public float MinPauseSeconds { get; set; } = 0.75f;
	[Property, Range( 0.25f, 8f )] public float MaxPauseSeconds { get; set; } = 2.25f;

	float _respawnAt;
	bool _hiddenForDeath;
	Vector3 _homePosition;
	Vector3 _moveTarget;
	float _pauseUntil;
	PlayerRole _appliedTeamRole = PlayerRole.Spectator;
	CharacterController _controller;

	protected override void OnStart()
	{
		ResolveRefs();
		_homePosition = WorldPosition;
		PickMoveTarget();
		ApplyTeamVisual();

		if ( Health.IsValid() )
			Health.OnKilled += OnKilled;
	}

	protected override void OnDestroy()
	{
		if ( Health.IsValid() )
			Health.OnKilled -= OnKilled;
	}

	protected override void OnUpdate()
	{
		ResolveRefs();
		ApplyTeamVisual();

		var wishVelocity = GetWishVelocity();
		if ( AnimationHelper.IsValid() )
		{
			AnimationHelper.WithVelocity( _controller.IsValid() ? _controller.Velocity : Vector3.Zero );
			AnimationHelper.WithWishVelocity( wishVelocity );
			AnimationHelper.IsGrounded = true;
			AnimationHelper.MoveStyle = CitizenAnimationHelper.MoveStyles.Walk;
		}

		// Respawn timer.
		if ( _hiddenForDeath && Time.Now >= _respawnAt && Networking.IsHost )
			Respawn();
	}

	protected override void OnFixedUpdate()
	{
		if ( !Networking.IsHost ) return;
		if ( _hiddenForDeath ) return;
		if ( !MoveAround ) return;

		ResolveRefs();
		if ( !_controller.IsValid() ) return;

		var wishVelocity = GetWishVelocity();

		if ( _controller.IsOnGround )
		{
			_controller.Velocity = _controller.Velocity.WithZ( 0 );
			_controller.Accelerate( wishVelocity );
			_controller.ApplyFriction( 3.5f );
		}
		else
		{
			_controller.Velocity -= Vector3.Up * 800f * Time.Delta * 0.5f;
			_controller.Accelerate( wishVelocity.ClampLength( 40f ) );
			_controller.ApplyFriction( 0.1f );
		}

		_controller.Move();

		if ( !_controller.IsOnGround )
			_controller.Velocity -= Vector3.Up * 800f * Time.Delta * 0.5f;

		FaceMoveDirection();
	}

	public void SetHomePosition( Vector3 position )
	{
		_homePosition = position;
		PickMoveTarget();
	}

	void OnKilled( DamageInfo info )
	{
		if ( _hiddenForDeath ) return;
		_hiddenForDeath = true;
		_respawnAt = Time.Now + RespawnSeconds;
		SetBodyVisible( false );
		if ( _controller.IsValid() )
			_controller.Enabled = false;
	}

	void Respawn()
	{
		_hiddenForDeath = false;
		WorldPosition = _homePosition;
		PickMoveTarget();

		if ( Health.IsValid() )
		{
			Health.Revive();
		}

		if ( _controller.IsValid() )
		{
			_controller.Enabled = true;
			_controller.Velocity = Vector3.Zero;
		}

		SetBodyVisible( true );
	}

	Vector3 GetWishVelocity()
	{
		if ( _hiddenForDeath || !MoveAround || Time.Now < _pauseUntil )
			return Vector3.Zero;

		var toTarget = (_moveTarget - WorldPosition).WithZ( 0 );
		if ( toTarget.Length < 24f )
		{
			_pauseUntil = Time.Now + RandomRange( MinPauseSeconds, MaxPauseSeconds );
			PickMoveTarget();
			return Vector3.Zero;
		}

		return toTarget.Normal * MoveSpeed;
	}

	void PickMoveTarget()
	{
		var angle = RandomRange( 0f, MathF.PI * 2f );
		var distance = RandomRange( WanderRadius * 0.35f, WanderRadius );
		_moveTarget = _homePosition + new Vector3( MathF.Cos( angle ) * distance, MathF.Sin( angle ) * distance, 0f );
	}

	void FaceMoveDirection()
	{
		if ( !Body.IsValid() || !_controller.IsValid() ) return;

		var flatVelocity = _controller.Velocity.WithZ( 0 );
		if ( flatVelocity.Length < 8f ) return;

		var target = Rotation.LookAt( flatVelocity.Normal, Vector3.Up );
		Body.WorldRotation = Rotation.Lerp( Body.WorldRotation, target, Time.Delta * 6f );
	}

	void ApplyTeamVisual()
	{
		if ( !Body.IsValid() || _appliedTeamRole == TeamRole ) return;

		var tint = TeamRole == PlayerRole.Pilot
			? new Color( 0.25f, 0.78f, 1f, 1f )
			: new Color( 0.9f, 0.48f, 0.24f, 1f );

		foreach ( var renderer in Body.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			renderer.Tint = tint;

		_appliedTeamRole = TeamRole;
	}

	void SetBodyVisible( bool visible )
	{
		if ( !Body.IsValid() ) return;
		var renderType = visible
			? ModelRenderer.ShadowRenderType.On
			: ModelRenderer.ShadowRenderType.ShadowsOnly;
		foreach ( var r in Body.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			r.RenderType = renderType;
	}

	void ResolveRefs()
	{
		if ( !Body.IsValid() )
			Body = GameObject.Children.FirstOrDefault( x => x.Name == "Body" );

		if ( !Health.IsValid() )
			Health = Components.Get<Health>();

		if ( !_controller.IsValid() )
			_controller = Components.Get<CharacterController>();

		if ( !AnimationHelper.IsValid() && Body.IsValid() )
		{
			if ( Body.Components.TryGet<CitizenAnimationHelper>( out var h, FindMode.EverythingInSelfAndDescendants ) )
				AnimationHelper = h;
		}
	}

	static float RandomRange( float min, float max )
	{
		if ( max <= min ) return min;
		return min + (float)System.Random.Shared.NextDouble() * (max - min);
	}
}
