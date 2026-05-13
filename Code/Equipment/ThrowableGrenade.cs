using Sandbox;
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
	[Property] public float FuseSeconds { get; set; } = 1.5f;
	[Property] public float ThrowRange { get; set; } = 900f;
	[Property] public float ThrowSpeed { get; set; } = 950f;
	[Property] public float Cooldown { get; set; } = 4f;
	[Property] public string ThrowInput { get; set; } = "Attack1";
	[Property] public float ThrowArcHeight { get; set; } = 55f;
	[Property] public Vector3 ProjectileGravity { get; set; } = new( 0f, 0f, 800f );
	[Property] public float ProjectileRestOffset { get; set; } = 2.5f;
	[Property] public float ProjectileSpinDegreesPerSecond { get; set; } = 540f;

	/// <summary>One-shot played at the thrower's position when the grenade leaves the hand.</summary>
	[Property] public SoundEvent ThrowSound { get; set; }

	/// <summary>One-shot played at the detonation point when the fuse expires.</summary>
	[Property] public SoundEvent DetonateSound { get; set; }

	[Property] public GameObject WeaponVisual { get; set; }
	[Property] public Vector3 FirstPersonOffset { get; set; } = new( 28f, 8f, -10f );
	[Property] public Angles FirstPersonRotationOffset { get; set; } = new( 0f, 0f, 0f );
	[Property] public Vector3 ThirdPersonLocalPosition { get; set; } = new( 12f, 14f, 48f );
	[Property] public Angles ThirdPersonLocalAngles { get; set; } = new( 0f, 0f, 0f );

	/// <summary>Loadout slot this grenade occupies. Defaults to the equipment slot.</summary>
	[Property] public int Slot { get; set; } = SoldierLoadout.EquipmentSlot;

	[Sync] public bool HasLiveProjectile { get; set; }
	[Sync] public float FuseEndTime { get; set; }

	TimeSince _timeSinceThrow = 100f;
	float _predictedProjectileEndTime;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );

	public bool IsArmed => HasLiveProjectile || Time.Now < _predictedProjectileEndTime;
	public bool IsReady => !IsArmed && CooldownRemaining <= 0f;
	public float FuseRemaining => IsArmed
		? MathF.Max( 0f, MathF.Max( FuseEndTime, _predictedProjectileEndTime ) - Time.Now )
		: 0f;
	public float CooldownRemaining => IsArmed ? 0f : MathF.Max( 0f, Cooldown - _timeSinceThrow );
	public float CooldownReadyFraction => Cooldown <= 0f
		? 1f
		: (1f - CooldownRemaining / Cooldown).Clamp( 0f, 1f );

	protected override void OnStart()
	{
		ApplySelectionVisualState();
	}

	protected override void OnUpdate()
	{
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

		if ( IsSelected && !IsArmed && _timeSinceThrow >= Cooldown && Input.Pressed( ThrowInput ) )
			BeginThrow();
	}

	internal bool ApplySelectionVisualState()
	{
		var visibleInHand = IsSelected && !IsArmed;
		WeaponPose.SetVisibility( GameObject, visibleInHand );
		return visibleInHand;
	}

	void BeginThrow()
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var origin = GetThrowOrigin( pc );
		var velocity = GetThrowVelocity( pc );
		var modelPath = ResolveVisualModelPath();

		_predictedProjectileEndTime = Time.Now + FuseSeconds;
		ServerThrow( origin, velocity, modelPath );
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

	Vector3 GetThrowVelocity( GroundPlayerController pc )
	{
		var dir = FlattenThrowDirection( pc.EyeAngles.ToRotation().Forward );
		var lift = Vector3.Up * MathF.Max( 0f, ThrowArcHeight * 4f );
		return dir * MathF.Max( 1f, ThrowSpeed ) + lift;
	}

	static Vector3 FlattenThrowDirection( Vector3 aim )
	{
		var flat = aim.WithZ( 0f );
		if ( flat.IsNearZeroLength )
			return aim.IsNearZeroLength ? Vector3.Forward : aim.Normal;

		var z = aim.z.Clamp( -0.22f, 0.12f );
		return (flat.Normal + Vector3.Up * z).Normal;
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
	void ServerThrow( Vector3 origin, Vector3 velocity, string modelPath )
	{
		if ( !CanMutateState() ) return;
		if ( HasLiveProjectile || _timeSinceThrow < Cooldown ) return;

		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		HasLiveProjectile = true;
		FuseEndTime = Time.Now + FuseSeconds;
		_timeSinceThrow = 0f;

		BroadcastThrowSound( origin );
		SpawnProjectile( pc.GameObject, origin, velocity, modelPath );
	}

	void SpawnProjectile( GameObject ignoreRoot, Vector3 origin, Vector3 velocity, string modelPath )
	{
		var projectileObject = new GameObject( true, $"{GetType().Name} Projectile" )
		{
			NetworkMode = NetworkMode.Object,
			WorldPosition = origin,
			WorldRotation = velocity.IsNearZeroLength ? WorldRotation : Rotation.LookAt( velocity.Normal )
		};

		if ( !string.IsNullOrWhiteSpace( modelPath ) )
		{
			var renderer = projectileObject.Components.Create<ModelRenderer>();
			renderer.Model = Model.Load( modelPath );
		}
		else
		{
			Log.Warning( $"[{GetType().Name}] No model found for thrown grenade projectile." );
		}

		var projectile = projectileObject.Components.Create<ThrownGrenadeProjectile>();
		projectile.Configure(
			this,
			ignoreRoot,
			velocity,
			ProjectileGravity,
			FuseSeconds,
			ProjectileRestOffset,
			ProjectileSpinDegreesPerSecond );

		if ( Networking.IsActive )
			projectileObject.NetworkSpawn();
	}

	[Rpc.Broadcast]
	void BroadcastThrowSound( Vector3 from )
	{
		if ( ThrowSound is not null )
			Sound.Play( ThrowSound, from );
	}

	[Rpc.Broadcast]
	void PlayDetonateSound( Vector3 position )
	{
		if ( DetonateSound is not null )
			Sound.Play( DetonateSound, position );
	}

	static bool CanMutateState() => !Networking.IsActive || Networking.IsHost;
}
