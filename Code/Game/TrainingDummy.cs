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
	const int HumanBodyGroupVisible = 0;
	const string SoldierHumanSkin = "Skin02";
	const string PilotHumanSkin = "Skin04";

	[Property, Range( 1f, 30f )] public float RespawnSeconds { get; set; } = 4f;
	[Property, Sync] public PlayerRole TeamRole { get; set; } = PlayerRole.Soldier;
	[Property] public GameObject Body { get; set; }
	[Property] public CitizenAnimationHelper AnimationHelper { get; set; }
	[Property] public Health Health { get; set; }
	[Property] public NavMeshAgent NavAgent { get; set; }
	[Property] public bool MoveAround { get; set; } = true;
	[Property] public bool UseNavMeshNavigation { get; set; } = true;
	[Property] public bool PressureNearestEnemy { get; set; } = true;
	[Property, Range( 0f, 512f )] public float WanderRadius { get; set; } = 220f;
	[Property, Range( 0f, 240f )] public float MoveSpeed { get; set; } = 75f;
	[Property, Range( 128f, 2500f )] public float EnemyPressureRadius { get; set; } = 900f;
	[Property, Range( 48f, 360f )] public float EnemyHoldDistance { get; set; } = 130f;
	[Property, Range( 8f, 64f )] public float NavAgentRadius { get; set; } = 18f;
	[Property, Range( 48f, 120f )] public float NavAgentHeight { get; set; } = 72f;
	[Property, Range( 0.25f, 8f )] public float MinPauseSeconds { get; set; } = 0.75f;
	[Property, Range( 0.25f, 8f )] public float MaxPauseSeconds { get; set; } = 2.25f;

	float _respawnAt;
	bool _hiddenForDeath;
	Vector3 _homePosition;
	Vector3 _moveTarget;
	float _pauseUntil;
	PlayerRole _appliedTeamRole = PlayerRole.Spectator;
	CharacterController _controller;
	Vector3 _lastNavTarget;
	TimeSince _timeSinceNavTargetRefresh = 999f;

	protected override void OnStart()
	{
		ResolveRefs();
		ConfigureNavAgent();
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
		ConfigureNavAgent();
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
		ConfigureNavAgent();
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

		if ( UseNavMeshNavigation && NavAgent.IsValid() )
			NavAgent.SetAgentPosition( WorldPosition );

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

		if ( TryGetNavWishVelocity( out var navWishVelocity ) )
			return navWishVelocity;

		var toTarget = (_moveTarget - WorldPosition).WithZ( 0 );
		if ( toTarget.Length < 24f )
		{
			_pauseUntil = Time.Now + RandomRange( MinPauseSeconds, MaxPauseSeconds );
			PickMoveTarget();
			return Vector3.Zero;
		}

		return toTarget.Normal * MoveSpeed;
	}

	bool TryGetNavWishVelocity( out Vector3 wishVelocity )
	{
		wishVelocity = Vector3.Zero;
		if ( !UseNavMeshNavigation || !NavAgent.IsValid() || Scene?.NavMesh is null )
			return false;

		var target = ResolveDesiredMoveTarget();
		var toTarget = (target - WorldPosition).WithZ( 0f );
		if ( toTarget.Length < 24f )
		{
			_pauseUntil = Time.Now + RandomRange( MinPauseSeconds, MaxPauseSeconds );
			NavAgent.Stop();
			PickMoveTarget();
			return true;
		}

		NavAgent.SetAgentPosition( WorldPosition );
		if ( _timeSinceNavTargetRefresh > 0.75f || target.Distance( _lastNavTarget ) > 64f || !NavAgent.IsNavigating )
		{
			_lastNavTarget = target;
			_timeSinceNavTargetRefresh = 0f;
			NavAgent.MoveTo( target );
		}

		wishVelocity = NavAgent.WishVelocity.WithZ( 0f );
		if ( wishVelocity.Length < 2f )
			wishVelocity = toTarget.Normal * MoveSpeed;

		wishVelocity = wishVelocity.ClampLength( MoveSpeed );
		return true;
	}

	Vector3 ResolveDesiredMoveTarget()
	{
		if ( PressureNearestEnemy && TryFindNearestEnemy( out var enemyPosition ) )
		{
			var toEnemy = (enemyPosition - WorldPosition).WithZ( 0f );
			if ( toEnemy.Length > EnemyHoldDistance )
				return enemyPosition;
		}

		return _moveTarget;
	}

	void PickMoveTarget()
	{
		if ( UseNavMeshNavigation && Scene?.NavMesh is not null )
		{
			var randomPoint = Scene.NavMesh.GetRandomPoint( _homePosition, MathF.Max( 64f, WanderRadius ) );
			if ( randomPoint.HasValue )
			{
				_moveTarget = randomPoint.Value;
				return;
			}
		}

		var angle = RandomRange( 0f, MathF.PI * 2f );
		var distance = RandomRange( WanderRadius * 0.35f, WanderRadius );
		_moveTarget = _homePosition + new Vector3( MathF.Cos( angle ) * distance, MathF.Sin( angle ) * distance, 0f );
	}

	bool TryFindNearestEnemy( out Vector3 position )
	{
		position = Vector3.Zero;
		var bestDistance = MathF.Max( 0f, EnemyPressureRadius );
		var found = false;

		foreach ( var ground in Scene.GetAllComponents<GroundPlayerController>() )
		{
			if ( !ground.IsValid() )
				continue;

			var role = ResolvePawnRole( ground.GameObject );
			if ( !IsOpposingRole( role ) )
				continue;

			var distance = ground.WorldPosition.Distance( WorldPosition );
			if ( distance >= bestDistance )
				continue;

			bestDistance = distance;
			position = ground.WorldPosition;
			found = true;
		}

		foreach ( var drone in Scene.GetAllComponents<DroneController>() )
		{
			if ( !drone.IsValid() || !IsOpposingRole( PlayerRole.Pilot ) )
				continue;

			var distance = drone.WorldPosition.Distance( WorldPosition );
			if ( distance >= bestDistance )
				continue;

			bestDistance = distance;
			position = drone.WorldPosition;
			found = true;
		}

		return found;
	}

	PlayerRole ResolvePawnRole( GameObject pawn )
	{
		if ( !pawn.IsValid() )
			return PlayerRole.Spectator;

		if ( pawn.Components.Get<PilotSoldier>( FindMode.EverythingInSelfAndDescendants ).IsValid() )
			return PlayerRole.Pilot;

		if ( pawn.Components.Get<SoldierBase>( FindMode.EverythingInSelfAndDescendants ).IsValid() )
			return PlayerRole.Soldier;

		return PlayerRole.Spectator;
	}

	bool IsOpposingRole( PlayerRole role )
	{
		return role is PlayerRole.Pilot or PlayerRole.Soldier && role != TeamRole;
	}

	void ConfigureNavAgent()
	{
		if ( !UseNavMeshNavigation )
			return;

		if ( !NavAgent.IsValid() )
			NavAgent = Components.Get<NavMeshAgent>();

		if ( !NavAgent.IsValid() && Networking.IsHost )
			NavAgent = Components.Create<NavMeshAgent>();

		if ( !NavAgent.IsValid() )
			return;

		NavAgent.UpdatePosition = false;
		NavAgent.UpdateRotation = false;
		NavAgent.Height = NavAgentHeight;
		NavAgent.Radius = NavAgentRadius;
		NavAgent.MaxSpeed = MoveSpeed;
		NavAgent.Acceleration = MathF.Max( MoveSpeed * 4f, 120f );
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

		foreach ( var renderer in Body.Components.GetAll<ModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
		{
			renderer.Tint = Color.White;
			renderer.MaterialGroup = TeamRole == PlayerRole.Pilot ? PilotHumanSkin : SoldierHumanSkin;

			if ( renderer is SkinnedModelRenderer skinned )
				ApplyFullHumanBodyGroups( skinned );
		}

		_appliedTeamRole = TeamRole;
	}

	static void ApplyFullHumanBodyGroups( SkinnedModelRenderer renderer )
	{
		renderer.SetBodyGroup( "Head", HumanBodyGroupVisible );
		renderer.SetBodyGroup( "Chest", HumanBodyGroupVisible );
		renderer.SetBodyGroup( "Legs", HumanBodyGroupVisible );
		renderer.SetBodyGroup( "Hands", HumanBodyGroupVisible );
		renderer.SetBodyGroup( "Feet", HumanBodyGroupVisible );
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

		if ( UseNavMeshNavigation && !NavAgent.IsValid() )
			NavAgent = Components.Get<NavMeshAgent>();

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
