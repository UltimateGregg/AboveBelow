using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Base for any thrown grenade. Owns throw input, cooldown, projectile spawn,
/// and detonation dispatch; subclasses implement <see cref="OnDetonate"/>.
/// </summary>
[Title( "Throwable Grenade" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "egg" )]
public abstract class ThrowableGrenade : Component
{
	const string DefaultProjectilePrefabPath = "prefabs/items/thrown_grenade_projectile.prefab";

	[Property] public float FuseSeconds { get; set; } = 1.5f;
	[Property] public float ThrowRange { get; set; } = 900f;
	[Property] public float ThrowSpeed { get; set; } = 950f;
	[Property] public float Cooldown { get; set; } = 4f;
	[Property] public string ThrowInput { get; set; } = "Attack1";
	[Property] public string AltThrowInput { get; set; } = "Attack2";
	[Property] public float ThrowArcHeight { get; set; } = 55f;
	[Property] public bool CookOnHold { get; set; } = true;
	[Property, Range( 0.1f, 1f )] public float AltThrowSpeedScale { get; set; } = 0.55f;
	[Property] public bool DropOnOwnerDeath { get; set; } = true;
	[Property] public Vector3 ProjectileGravity { get; set; } = new( 0f, 0f, 800f );
	[Property] public float ProjectileRestOffset { get; set; } = 2.5f;
	[Property] public float ProjectileSpinDegreesPerSecond { get; set; } = 540f;
	[Property] public float ProjectileColliderRadius { get; set; } = 5.5f;
	[Property] public float ProjectileColliderLength { get; set; } = 18f;
	[Property] public float ProjectileMass { get; set; } = 1.2f;
	[Property] public float ProjectileLinearDamping { get; set; } = 0.18f;
	[Property] public float ProjectileAngularDamping { get; set; } = 0.75f;
	[Property] public float ProjectileElasticity { get; set; } = 0.32f;
	[Property] public float ProjectileFriction { get; set; } = 0.8f;
	[Property] public float ProjectileRollingResistance { get; set; } = 0.45f;
	[Property, Range( 0f, 20f )] public float ProjectileSleepThreshold { get; set; } = 2f;
	[Property] public float ProjectileSpinMin { get; set; } = 420f;
	[Property] public float ProjectileSpinMax { get; set; } = 980f;
	[Property] public float ProjectileOwnerCollisionGraceSeconds { get; set; } = 0.12f;

	/// <summary>One-shot played at the thrower's position when the grenade leaves the hand.</summary>
	[Property] public SoundEvent ThrowSound { get; set; }

	/// <summary>One-shot played at the detonation point when the fuse expires.</summary>
	[Property] public SoundEvent DetonateSound { get; set; }

	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public GameObject LeftHandIkTarget { get; set; }
	[Property] public GameObject RightHandIkTarget { get; set; }
	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 28f, 8f, -10f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 12f, 14f, 48f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );
	[Property] public CitizenAnimationHelper.HoldTypes HoldType { get; set; } = CitizenAnimationHelper.HoldTypes.HoldItem;
	[Property] public CitizenAnimationHelper.Hand Handedness { get; set; } = CitizenAnimationHelper.Hand.Right;

	/// <summary>Loadout slot this grenade occupies. Defaults to the equipment slot.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.EquipmentSlot;

	[Sync] public bool HasLiveProjectile { get; set; }
	[Sync] public float FuseEndTime { get; set; }

	TimeSince _timeSinceThrow = 100f;
	float _predictedProjectileEndTime;
	bool _isCooking;
	float _cookStartedAt;
	Health _ownerHealth;
	Action<DamageInfo> _ownerKillHandler;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );

	public bool IsArmed => HasLiveProjectile || _isCooking || Time.Now < _predictedProjectileEndTime;
	public bool IsReady => !IsArmed && CooldownRemaining <= 0f;
	public float FuseRemaining => IsArmed
		? MathF.Max( 0f, MathF.Max( MathF.Max( FuseEndTime, _predictedProjectileEndTime ), _isCooking ? _cookStartedAt + FuseSeconds : 0f ) - Time.Now )
		: 0f;
	public float CooldownRemaining => IsArmed ? 0f : MathF.Max( 0f, Cooldown - _timeSinceThrow );
	public float CooldownReadyFraction => Cooldown <= 0f
		? 1f
		: (1f - CooldownRemaining / Cooldown).Clamp( 0f, 1f );

	protected override void OnStart()
	{
		ResolvePrefabReferences();
		ApplySelectionVisualState();
	}

	protected override void OnDestroy()
	{
		UnhookOwnerHealth();
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();

		// Hold-in-hand visibility + FPS viewmodel pose run for everyone so
		// remote players see the grenade attached to the body, and so the
		// local player sees it bob with their camera when selected.
		var visibleInHand = ApplySelectionVisualState();
		if ( visibleInHand )
		{
			WeaponPose.UpdateViewmodel(
				this, IsProxy,
				FirstPersonOffset, FirstPersonRotationOffset,
				ThirdPersonLocalPosition, ThirdPersonLocalAngles );
		}

		if ( IsProxy ) return;
		if ( LocalOptionsState.ConsumesGameplayInput ) return;

		if ( _isCooking )
		{
			if ( FuseRemaining <= 0.05f || Input.Released( ThrowInput ) )
				ReleaseCookedThrow( false );
			return;
		}

		if ( !IsSelected || IsArmed || _timeSinceThrow < Cooldown )
			return;

		if ( Input.Pressed( ThrowInput ) )
		{
			if ( CookOnHold )
				StartCookingThrow();
			else
				BeginThrow( Input.Down( AltThrowInput ), FuseSeconds );
		}
	}

	internal bool ApplySelectionVisualState()
	{
		var visibleInHand = IsSelected && !HasLiveProjectile;
		var visible = visibleInHand && !FirstPersonViewmodel.ShouldHideWorldHeldItem( this, visibleInHand );
		WeaponPose.SetVisibility( GameObject, visible );
		WeaponPose.ApplyHandPose( this, visible, HoldType, Handedness, LeftHandIkTarget, RightHandIkTarget );
		return visibleInHand;
	}

	void ResolvePrefabReferences()
	{
		if ( !WeaponVisual.IsValid() )
			WeaponVisual = GameObject.Children.FirstOrDefault( x => x.Name == "WeaponVisual" );

		if ( !LeftHandIkTarget.IsValid() )
			LeftHandIkTarget = GameObject.Children.FirstOrDefault( x => x.Name == "LeftHandIk" );

		if ( !RightHandIkTarget.IsValid() )
			RightHandIkTarget = GameObject.Children.FirstOrDefault( x => x.Name == "RightHandIk" );
	}

	void StartCookingThrow()
	{
		if ( _isCooking )
			return;

		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() )
			return;

		_isCooking = true;
		_cookStartedAt = Time.Now;
		_predictedProjectileEndTime = Time.Now + FuseSeconds;
		HookOwnerHealth();
	}

	void ReleaseCookedThrow( bool forceDrop )
	{
		if ( !_isCooking )
			return;

		var elapsed = MathF.Max( 0f, Time.Now - _cookStartedAt );
		var remainingFuse = MathF.Max( 0.05f, FuseSeconds - elapsed );
		var alternateThrow = !forceDrop && Input.Down( AltThrowInput );
		_isCooking = false;
		UnhookOwnerHealth();
		BeginThrow( alternateThrow, remainingFuse, forceDrop );
	}

	void BeginThrow( bool alternateThrow, float fuseSeconds, bool forceDrop = false )
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var origin = forceDrop ? WorldPosition + Vector3.Up * ProjectileRestOffset : GetThrowOrigin( pc );
		var velocity = forceDrop ? GetDropVelocity( pc ) : GetThrowVelocity( pc, alternateThrow );
		var modelPath = ResolveVisualModelPath();

		_predictedProjectileEndTime = Time.Now + MathF.Max( 0.05f, fuseSeconds );
		ServerThrow( origin, velocity, modelPath, fuseSeconds );
		_timeSinceThrow = 0f;
	}

	Vector3 GetThrowOrigin( GroundPlayerController pc )
	{
		var look = pc.EyeAngles.ToRotation();
		var eyePos = pc.Eye.IsValid() ? pc.Eye.WorldPosition : pc.WorldPosition + Vector3.Up * 64f;
		var heldPos = WorldPosition;

		if ( (heldPos - eyePos).Length < 160f )
			return heldPos + look.Forward * 8f;

		return eyePos
			+ look.Forward * MathF.Max( 24f, FirstPersonOffset.x * 0.85f )
			+ look.Right * FirstPersonOffset.y
			+ look.Up * FirstPersonOffset.z;
	}

	Vector3 GetThrowVelocity( GroundPlayerController pc, bool alternateThrow )
	{
		var dir = FlattenThrowDirection( pc.EyeAngles.ToRotation().Forward );
		var speedScale = alternateThrow ? AltThrowSpeedScale.Clamp( 0.1f, 1f ) : 1f;
		var lift = Vector3.Up * MathF.Max( 0f, ThrowArcHeight * 4f * speedScale );
		return dir * MathF.Max( 1f, ThrowSpeed * speedScale ) + lift;
	}

	Vector3 GetDropVelocity( GroundPlayerController pc )
	{
		var forward = pc.EyeAngles.ToRotation().Forward.WithZ( 0f );
		if ( forward.IsNearZeroLength )
			forward = Vector3.Forward;

		return forward.Normal * MathF.Max( 48f, ThrowSpeed * 0.12f ) + Vector3.Up * MathF.Max( 32f, ThrowArcHeight );
	}

	static Vector3 FlattenThrowDirection( Vector3 aim )
	{
		var flat = aim.WithZ( 0f );
		if ( flat.IsNearZeroLength )
			return aim.IsNearZeroLength ? Vector3.Forward : aim.Normal;

		var z = aim.z.Clamp( -0.22f, 0.12f );
		return (flat.Normal + Vector3.Up * z).Normal;
	}

	void HookOwnerHealth()
	{
		if ( !DropOnOwnerDeath || _ownerKillHandler is not null )
			return;

		_ownerHealth = Components.GetInAncestors<Health>();
		if ( !_ownerHealth.IsValid() )
			return;

		_ownerKillHandler = _ => ReleaseCookedThrow( true );
		_ownerHealth.OnKilled += _ownerKillHandler;
	}

	void UnhookOwnerHealth()
	{
		if ( _ownerHealth.IsValid() && _ownerKillHandler is not null )
			_ownerHealth.OnKilled -= _ownerKillHandler;

		_ownerHealth = null;
		_ownerKillHandler = null;
	}

	internal void ResolveProjectileDetonation( ThrownGrenadeProjectile projectile, Vector3 position )
	{
		if ( !CanMutateState() ) return;
		if ( projectile is null || !projectile.IsValid() ) return;

		HasLiveProjectile = false;
		FuseEndTime = 0f;
		_predictedProjectileEndTime = 0f;

		PlayDetonateSound( position );
		OnDetonate( position );
	}

	/// <summary>
	/// Called when the live projectile detonates. Implementations should issue
	/// the right RPCs themselves.
	/// </summary>
	protected abstract void OnDetonate( Vector3 worldPos );

	string ResolveVisualModelPath()
	{
		var renderRoot = WeaponVisual.IsValid() ? WeaponVisual : GameObject;
		if ( !renderRoot.IsValid() ) return "";

		var renderer = renderRoot.Components.Get<ModelRenderer>( FindMode.EverythingInSelfAndDescendants );
		if ( !renderer.IsValid() || renderer.Model is null || !renderer.Model.IsValid )
			return "";

		return renderer.Model.Name ?? "";
	}

	[Rpc.Broadcast]
	void ServerThrow( Vector3 origin, Vector3 velocity, string modelPath, float fuseSeconds )
	{
		if ( !CanMutateState() ) return;
		if ( HasLiveProjectile || _timeSinceThrow < Cooldown ) return;

		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var clampedFuse = MathF.Max( 0.05f, fuseSeconds );
		HasLiveProjectile = true;
		FuseEndTime = Time.Now + clampedFuse;
		_timeSinceThrow = 0f;

		BroadcastThrowSound( origin );
		SpawnProjectile( pc.GameObject, origin, velocity, modelPath, clampedFuse );
	}

	void SpawnProjectile( GameObject ignoreRoot, Vector3 origin, Vector3 velocity, string modelPath, float fuseSeconds )
	{
		var projectileRotation = velocity.IsNearZeroLength ? WorldRotation : Rotation.LookAt( velocity.Normal );
		var projectileName = $"{GetType().Name} Projectile";
		var projectilePrefab = GameObject.GetPrefab( DefaultProjectilePrefabPath );
		var projectileObject = projectilePrefab.IsValid()
			? projectilePrefab.Clone( new Transform( origin, projectileRotation ), name: projectileName )
			: new GameObject( true, projectileName );

		projectileObject.NetworkMode = NetworkMode.Object;
		projectileObject.WorldPosition = origin;
		projectileObject.WorldRotation = projectileRotation;

		if ( !string.IsNullOrWhiteSpace( modelPath ) )
		{
			var renderer = projectileObject.Components.Get<ModelRenderer>();
			if ( !renderer.IsValid() )
				renderer = projectileObject.Components.Create<ModelRenderer>();
			renderer.Model = Model.Load( modelPath );
		}
		else
		{
			Log.Warning( $"[{GetType().Name}] No model found for thrown grenade projectile." );
		}

		var projectile = projectileObject.Components.Get<ThrownGrenadeProjectile>();
		if ( !projectile.IsValid() )
			projectile = projectileObject.Components.Create<ThrownGrenadeProjectile>();
		projectile.Configure(
			this,
			ignoreRoot,
			velocity,
			ProjectileGravity,
			fuseSeconds,
			ProjectileColliderRadius,
			ProjectileColliderLength,
			ProjectileMass,
			ProjectileLinearDamping,
			ProjectileAngularDamping,
			ProjectileElasticity,
			ProjectileFriction,
			ProjectileRollingResistance,
			ProjectileSleepThreshold,
			ProjectileSpinMin,
			ProjectileSpinMax,
			ProjectileOwnerCollisionGraceSeconds );

		// SpawnProjectile is only reached from ServerThrow after CanMutateState().
		if ( Networking.IsActive )
			projectileObject.NetworkSpawn();
	}

	[Rpc.Broadcast]
	void BroadcastThrowSound( Vector3 from )
	{
		if ( ThrowSound is not null )
			SoundPlayback.PlayAttached( ThrowSound, GameObject, from );
	}

	[Rpc.Broadcast]
	void PlayDetonateSound( Vector3 position )
	{
		if ( DetonateSound is not null )
			Sound.Play( DetonateSound, position );
	}

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;
}
