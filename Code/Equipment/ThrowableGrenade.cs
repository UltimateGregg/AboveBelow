using Sandbox;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Base for any thrown grenade. Owns the throw input + cooldown; subclasses
/// implement <see cref="OnDetonate"/>.
///
/// Implementation note: for a first pass we don't spawn a separate
/// projectile prefab. Instead, on throw we cache a target position
/// (eye + forward * range) and detonate after the fuse — the grenade is
/// "instant-toss" from a gameplay standpoint. A physics projectile can
/// replace this later.
/// </summary>
[Title( "Throwable Grenade" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "egg" )]
public abstract class ThrowableGrenade : Component
{
	[Property] public float FuseSeconds { get; set; } = 1.5f;
	[Property] public float ThrowRange { get; set; } = 900f;
	[Property] public float Cooldown { get; set; } = 4f;
	[Property] public string ThrowInput { get; set; } = "Attack1";
	[Property] public float ThrowArcHeight { get; set; } = 55f;

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

	TimeSince _timeSinceThrow = 100f;
	bool _armed;
	float _detonateAt;
	Vector3 _detonatePosition;

	public bool IsSelected => WeaponPose.IsSlotSelected( this, Slot );

	public bool IsArmed => _armed;
	public bool IsReady => !_armed && CooldownRemaining <= 0f;
	public float FuseRemaining => _armed ? MathF.Max( 0f, _detonateAt - Time.Now ) : 0f;
	public float CooldownRemaining => _armed ? 0f : MathF.Max( 0f, Cooldown - _timeSinceThrow );
	public float CooldownReadyFraction => Cooldown <= 0f
		? 1f
		: (1f - CooldownRemaining / Cooldown).Clamp( 0f, 1f );

	protected override void OnUpdate()
	{
		// Hold-in-hand visibility + FPS viewmodel pose run for everyone so
		// remote players see the grenade attached to the body, and so the
		// local player sees it bob with their camera when it's the selected
		// loadout slot.
		var visibleInHand = IsSelected && !_armed;
		WeaponPose.SetVisibility( GameObject, WeaponVisual, visibleInHand );
		if ( visibleInHand )
		{
			WeaponPose.UpdateViewmodel(
				this, IsProxy,
				FirstPersonOffset, FirstPersonRotationOffset,
				ThirdPersonLocalPosition, ThirdPersonLocalAngles );
		}

		if ( IsProxy ) return;

		// Throw input only fires when the grenade is the active loadout slot.
		// Detonation continues regardless — once thrown, the fuse is committed.
		if ( IsSelected && !_armed && _timeSinceThrow >= Cooldown && Input.Pressed( ThrowInput ) )
			BeginThrow();

		if ( _armed && Time.Now >= _detonateAt )
		{
			_armed = false;
			ResolveDetonation();
		}
	}

	void BeginThrow()
	{
		var pc = Components.GetInAncestors<GroundPlayerController>();
		if ( !pc.IsValid() ) return;

		var dir = FlattenThrowDirection( pc.EyeAngles.ToRotation().Forward );
		var origin = (pc.Eye?.WorldPosition ?? pc.WorldPosition + Vector3.Up * 64f) + dir * 32f + Vector3.Down * 10f;

		var tr = Scene.Trace
			.Ray( origin, origin + dir * ThrowRange )
			.IgnoreGameObjectHierarchy( pc.GameObject )
			.WithoutTags( "trigger" )
			.Run();

		_detonatePosition = tr.Hit ? tr.HitPosition : origin + dir * ThrowRange;
		_detonateAt = Time.Now + FuseSeconds;
		_armed = true;
		_timeSinceThrow = 0f;

		BroadcastThrowVisual( origin, _detonatePosition, ResolveVisualModelPath(), FuseSeconds, ThrowArcHeight );
	}

	static Vector3 FlattenThrowDirection( Vector3 aim )
	{
		var flat = aim.WithZ( 0f );
		if ( flat.IsNearZeroLength )
			return aim.IsNearZeroLength ? Vector3.Forward : aim.Normal;

		var z = aim.z.Clamp( -0.22f, 0.12f );
		return (flat.Normal + Vector3.Up * z).Normal;
	}

	void ResolveDetonation()
	{
		PlayDetonateSound( _detonatePosition );
		OnDetonate( _detonatePosition );
	}

	/// <summary>
	/// Called once the fuse expires. World position of the detonation is
	/// supplied. Implementations should issue the right RPCs themselves.
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
	void BroadcastThrowVisual( Vector3 from, Vector3 to, string modelPath, float duration, float arcHeight )
	{
		if ( ThrowSound is not null )
			Sound.Play( ThrowSound, from );

		if ( string.IsNullOrWhiteSpace( modelPath ) ) return;

		var visualObject = new GameObject( true, "Thrown Grenade Visual" )
		{
			NetworkMode = NetworkMode.Never,
			WorldPosition = from,
			WorldRotation = Rotation.LookAt( (to - from).Normal )
		};

		var renderer = visualObject.Components.Create<ModelRenderer>();
		renderer.Model = Model.Load( modelPath );

		var visual = visualObject.Components.Create<ThrownGrenadeVisual>();
		visual.Configure( from, to, duration, arcHeight );
	}

	[Rpc.Broadcast]
	void PlayDetonateSound( Vector3 position )
	{
		if ( DetonateSound is not null )
			Sound.Play( DetonateSound, position );
	}
}
