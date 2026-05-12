using Sandbox;
using Sandbox.Citizen;
using System;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// First/third person controller for Soldiers. Adapted from Facepunch's
/// scenestaging PlayerController reference, trimmed and renamed for this game.
/// Uses CharacterController for movement (kinematic, fits FPS gameplay).
///
/// Polish layers live here (Phase 1 + 3 + 4):
///   - <see cref="AddRecoil"/> — camera-only recoil decay; doesn't touch EyeAngles.
///   - View bob (procedural sine offset based on speed)
///   - Landing dip (camera pitch flick on hard landings)
///   - Footstep / jump / land sound triggers
///   - ADS state machine + FOV interpolation
///   - Sprint FOV widening + stamina drain
///   - Crouch (height + eye-Z + speed lerps)
///   - Slide-after-sprint (locks direction, decays velocity, force-crouched)
///
/// Weapons read <see cref="IsAds"/> and call <see cref="SetAdsTarget"/> each
/// frame to request ADS pose + sights FOV.
/// </summary>
[Title( "Ground Player Controller" )]
[Category( "Drone vs Players/Player" )]
[Icon( "directions_walk" )]
public sealed class GroundPlayerController : Component
{
	[Property] public Vector3 Gravity { get; set; } = new Vector3( 0, 0, 800 );
	[Property] public float WalkSpeed { get; set; } = 110f;
	[Property] public float SprintSpeed { get; set; } = 320f;
	[Property] public float JumpStrength { get; set; } = 322f;

	[Property] public GameObject Body { get; set; }
	[Property] public GameObject Eye { get; set; }
	[Property] public CitizenAnimationHelper AnimationHelper { get; set; }
	[Property] public bool FirstPerson { get; set; } = true;

	// ---- Camera FOV ----
	[Property, Range( 50f, 110f )] public float BaseFovDegrees { get; set; } = 80f;
	[Property, Range( 30f, 90f )]  public float DefaultAdsFovDegrees { get; set; } = 55f;
	[Property, Range( 0f, 30f )]   public float SprintFovBoost { get; set; } = 6f;
	[Property, Range( 0.5f, 30f )] public float FovLerpRate { get; set; } = 12f;

	// ---- ADS ----
	[Property, Range( 0.5f, 30f )] public float AdsLerpRate { get; set; } = 14f;
	[Property, Range( 0f, 1f )]    public float AdsMovementMultiplier { get; set; } = 0.55f;

	// ---- View bob / sway ----
	[Property, Range( 0f, 5f )]   public float ViewBobAmplitude { get; set; } = 0.6f;
	[Property, Range( 1f, 20f )]  public float ViewBobFrequencyWalk { get; set; } = 7f;
	[Property, Range( 1f, 25f )]  public float ViewBobFrequencySprint { get; set; } = 11f;

	// ---- Landing dip ----
	[Property, Range( 0f, 30f )]    public float LandingDipDegreesMax { get; set; } = 8f;
	[Property, Range( 200f, 2000f )] public float LandingDipSpeedReference { get; set; } = 800f;
	[Property, Range( 1f, 30f )]    public float LandingDipDecay { get; set; } = 8f;

	// ---- Footsteps ----
	[Property, Range( 8f, 80f )]    public float FootstepDistance { get; set; } = 36f;
	[Property] public SoundEvent FootstepSound { get; set; }
	[Property] public SoundEvent JumpSound { get; set; }
	[Property] public SoundEvent LandSound { get; set; }

	// ---- Crouch ----
	[Property, Range( 36f, 96f )] public float StandingHeight { get; set; } = 72f;
	[Property, Range( 24f, 60f )] public float CrouchHeight { get; set; } = 42f;
	[Property, Range( 24f, 96f )] public float StandingEyeZ { get; set; } = 64f;
	[Property, Range( 14f, 60f )] public float CrouchEyeZ { get; set; } = 36f;
	[Property, Range( 0.1f, 1f )] public float CrouchSpeedMultiplier { get; set; } = 0.55f;
	[Property, Range( 1f, 30f )]  public float CrouchLerpRate { get; set; } = 10f;

	// ---- Slide ----
	[Property, Range( 0.3f, 3f )]  public float SlideDuration { get; set; } = 1.1f;
	[Property, Range( 1f, 3f )]    public float SlideInitialBoost { get; set; } = 1.35f;
	[Property, Range( 0f, 30f )]   public float SlideDrag { get; set; } = 2.2f;
	[Property, Range( 0f, 30f )]   public float SlideCameraRollDegrees { get; set; } = 8f;

	// ---- Stamina ----
	[Property, Range( 1f, 30f )] public float StaminaMaxSeconds { get; set; } = 6f;
	[Property, Range( 1f, 30f )] public float StaminaRefillSeconds { get; set; } = 4f;
	[Property, Range( 0f, 1f )]  public float StaminaMinToSprint { get; set; } = 0.10f;

	public Vector3 WishVelocity { get; private set; }

	[Sync] public Angles EyeAngles { get; set; }
	[Sync] public bool IsSprinting { get; set; }
	[Sync] public float Stamina { get; set; } = 1f;          // 0..1, replicated for HUD
	[Sync] public bool IsCrouched { get; set; }              // for animgraph / observers
	[Sync] public bool IsSliding { get; set; }

	private CameraComponent _cachedCamera;

	// Recoil
	private Angles _recoilOffset;
	[Property, Range( 4f, 30f )] public float RecoilReturnRate { get; set; } = 12f;

	// ADS state (local-only)
	float _adsT;
	bool _adsRequested;
	float _adsTargetFov = 55f;

	// Landing dip state (local-only)
	float _landingDipPitch;
	bool _wasOnGround = true;
	float _lastAirborneVz;

	// Footstep state (local-only)
	float _stepAccumulator;

	// View bob phase (local-only)
	float _bobPhase;

	// Crouch / slide state (local-only)
	float _crouchT;              // 0 standing, 1 crouched
	float _slideTimeLeft;
	Vector3 _slideDirection;
	bool _prevDuckDown;

	// Suppression state (local-only). Set by HitscanWeapon when a bullet
	// passes nearby; decays each frame. Dampens look sensitivity + drives
	// HUD vignette/crosshair-bloom.
	float _suppressionT;
	[Property, Range( 0.2f, 5f )] public float SuppressionDecayRate { get; set; } = 1.4f;
	[Property, Range( 0f, 1f )]   public float SuppressionLookDampening { get; set; } = 0.4f;

	public bool IsAds => _adsT > 0.5f;
	public float AdsT => _adsT;
	public float CrouchT => _crouchT;
	public float SuppressionT => _suppressionT;

	/// <summary>
	/// Bump the local-player suppression factor (0..1). Decays over time at
	/// <see cref="SuppressionDecayRate"/>. Called by weapons when a hostile
	/// bullet trace passes near this player's eye position.
	/// </summary>
	public void AddSuppression( float amount )
	{
		_suppressionT = MathF.Min( 1f, _suppressionT + amount );
	}

	public void SetAdsTarget( bool wanted, float adsFov )
	{
		_adsRequested = wanted;
		if ( wanted ) _adsTargetFov = adsFov;
	}

	public void AddRecoil( float pitch, float yaw )
	{
		_recoilOffset.pitch -= pitch;
		_recoilOffset.yaw += yaw;
	}

	protected override void OnEnabled()
	{
		base.OnEnabled();
		ResolvePrefabReferences();
		if ( IsProxy ) return;

		_cachedCamera = Scene.GetAllComponents<CameraComponent>().FirstOrDefault();
		if ( _cachedCamera.IsValid() )
		{
			var ee = _cachedCamera.WorldRotation.Angles();
			ee.roll = 0;
			EyeAngles = ee;
			_cachedCamera.FieldOfView = BaseFovDegrees;
		}
		Stamina = 1f;
	}

	protected override void OnUpdate()
	{
		ResolvePrefabReferences();

		if ( !IsProxy )
		{
			try { HandleLook(); } catch ( System.Exception e ) { Log.Warning( $"HandleLook error: {e.Message}" ); }

			// Sprint requested? Gate on stamina (only if locally-owned).
			var wantsSprint = Input.Down( "Run" );
			var hasStamina = Stamina > StaminaMinToSprint;
			IsSprinting = wantsSprint && hasStamina && !IsCrouched && !IsSliding;
		}

		try { UpdateBodyAndAnims(); } catch ( System.Exception e ) { Log.Warning( $"UpdateBodyAndAnims error: {e.Message}" ); }
	}

	void HandleLook()
	{
		// Suppression damps look sensitivity proportionally. At max
		// suppression, sensitivity drops to (1 - SuppressionLookDampening).
		var lookScale = 0.5f * MathX.Lerp( 1f, 1f - SuppressionLookDampening, _suppressionT );
		var ee = EyeAngles;
		ee += Input.AnalogLook * lookScale;
		ee.pitch = ee.pitch.Clamp( -89f, 89f );
		ee.roll = 0;
		EyeAngles = ee;

		// Suppression decay (exponential).
		_suppressionT = MathX.Lerp( _suppressionT, 0f,
			1f - MathF.Exp( -SuppressionDecayRate * Time.Delta ) );

		if ( !_cachedCamera.IsValid() )
			_cachedCamera = Scene.GetAllComponents<CameraComponent>().FirstOrDefault();

		if ( !_cachedCamera.IsValid() ) return;

		// Recoil decay.
		var recoilDecay = 1f - MathF.Exp( -RecoilReturnRate * Time.Delta );
		_recoilOffset.pitch = MathX.Lerp( _recoilOffset.pitch, 0f, recoilDecay );
		_recoilOffset.yaw   = MathX.Lerp( _recoilOffset.yaw,   0f, recoilDecay );

		// ADS lerp. Sprinting / sliding forces ADS off.
		var wantsAds = _adsRequested && !IsSprinting && !IsSliding;
		_adsT = MathX.Lerp( _adsT, wantsAds ? 1f : 0f, 1f - MathF.Exp( -AdsLerpRate * Time.Delta ) );
		_adsRequested = false;

		// FOV: sprint widens, ADS narrows. ADS wins.
		var sprintFov = BaseFovDegrees + (IsSprinting ? SprintFovBoost : 0f);
		var targetFov = MathX.Lerp( sprintFov, _adsTargetFov, _adsT );
		_cachedCamera.FieldOfView = MathX.Lerp(
			_cachedCamera.FieldOfView, targetFov,
			1f - MathF.Exp( -FovLerpRate * Time.Delta ) );

		// Landing dip decay.
		_landingDipPitch = MathX.Lerp( _landingDipPitch, 0f,
			1f - MathF.Exp( -LandingDipDecay * Time.Delta ) );

		// Crouch lerp. Crouch input held OR sliding → target = 1.
		var wantsCrouch = (Input.Down( "Duck" ) || IsSliding) && !IsProxy;
		var crouchTarget = wantsCrouch ? 1f : 0f;
		_crouchT = MathX.Lerp( _crouchT, crouchTarget,
			1f - MathF.Exp( -CrouchLerpRate * Time.Delta ) );
		if ( !IsProxy ) IsCrouched = _crouchT > 0.5f;

		// Drop the Eye GameObject's local Z to crouched height; CharacterController
		// height adjusts in OnFixedUpdate so collisions track.
		if ( Eye.IsValid() )
		{
			var ezBase = MathX.Lerp( StandingEyeZ, CrouchEyeZ, _crouchT );
			var lp = Eye.LocalPosition;
			Eye.LocalPosition = new Vector3( lp.x, lp.y, ezBase );
		}

		var lookDir = EyeAngles.ToRotation();

		// Build display rotation: recoil pitch + landing dip + slide camera roll.
		var displayAngles = EyeAngles + _recoilOffset;
		displayAngles.pitch += _landingDipPitch;
		if ( IsSliding ) displayAngles.roll = SlideCameraRollDegrees;
		var displayDir = displayAngles.ToRotation();

		if ( Eye.IsValid() )
			Eye.WorldRotation = displayDir;

		// View bob — only when grounded + moving + not sliding. Bob is also
		// halved when crouched.
		var cc = Components.Get<CharacterController>();
		var bobOffset = Vector3.Zero;
		if ( cc.IsValid() && cc.IsOnGround && !IsSliding )
		{
			var horizSpeed = cc.Velocity.WithZ( 0 ).Length;
			var speedFrac = (horizSpeed / Math.Max( 1f, SprintSpeed )).Clamp( 0f, 1f );
			var bobFreq = IsSprinting ? ViewBobFrequencySprint : ViewBobFrequencyWalk;
			_bobPhase += Time.Delta * bobFreq;
			var crouchMul = MathX.Lerp( 1f, 0.5f, _crouchT );
			var bobIntensity = ViewBobAmplitude * speedFrac * MathX.Lerp( 1f, 0.5f, _adsT ) * crouchMul;
			var bobSide = MathF.Sin( _bobPhase ) * bobIntensity;
			var bobVert = MathF.Abs( MathF.Sin( _bobPhase ) ) * bobIntensity * 1.2f;
			bobOffset = displayDir.Right * bobSide + Vector3.Up * bobVert;
		}

		if ( FirstPerson && Eye.IsValid() )
		{
			_cachedCamera.WorldPosition = Eye.WorldPosition + bobOffset;
			_cachedCamera.WorldRotation = displayDir;
			SetBodyRenderType( ModelRenderer.ShadowRenderType.ShadowsOnly );
		}
		else
		{
			_cachedCamera.WorldPosition = WorldPosition + lookDir.Backward * 200f + Vector3.Up * 75f;
			_cachedCamera.WorldRotation = displayDir;
			SetBodyRenderType( ModelRenderer.ShadowRenderType.On );
		}
	}

	void SetBodyRenderType( ModelRenderer.ShadowRenderType renderType )
	{
		if ( !Body.IsValid() ) return;

		foreach ( var renderer in Body.Components.GetAll<SkinnedModelRenderer>( FindMode.EverythingInSelfAndDescendants ) )
			renderer.RenderType = renderType;
	}

	void UpdateBodyAndAnims()
	{
		var cc = Components.Get<CharacterController>();
		if ( !cc.IsValid() ) return;

		float moveRotationSpeed = 0;

		if ( Body.IsValid() )
		{
			var targetAngle = new Angles( 0, EyeAngles.yaw, 0 ).ToRotation();
			var v = cc.Velocity.WithZ( 0 );

			if ( v.Length > 10f )
				targetAngle = Rotation.LookAt( v, Vector3.Up );

			float rotateDifference = Body.WorldRotation.Distance( targetAngle );
			if ( rotateDifference > 50f || cc.Velocity.Length > 10f )
			{
				var newRotation = Rotation.Lerp( Body.WorldRotation, targetAngle, Time.Delta * 2f );
				var angleDiff = Body.WorldRotation.Angles() - newRotation.Angles();
				moveRotationSpeed = angleDiff.yaw / Time.Delta;
				Body.WorldRotation = newRotation;
			}
		}

		if ( AnimationHelper.IsValid() )
		{
			AnimationHelper.WithVelocity( cc.Velocity );
			AnimationHelper.WithWishVelocity( WishVelocity );
			AnimationHelper.IsGrounded = cc.IsOnGround;
			AnimationHelper.MoveRotationSpeed = moveRotationSpeed;
			AnimationHelper.WithLook( EyeAngles.Forward, 1, 1, 1f );
			AnimationHelper.DuckLevel = _crouchT;
			AnimationHelper.MoveStyle = IsSprinting
				? CitizenAnimationHelper.MoveStyles.Run
				: CitizenAnimationHelper.MoveStyles.Walk;
		}
	}

	protected override void OnFixedUpdate()
	{
		if ( IsProxy ) return;

		BuildWishVelocity();

		var cc = Components.Get<CharacterController>();
		if ( !cc.IsValid() ) return;

		// Lerp CharacterController height between standing and crouched.
		cc.Height = MathX.Lerp( StandingHeight, CrouchHeight, _crouchT );

		// Slide entry: sprinting + grounded + moving + Duck pressed THIS frame.
		var duckDown = Input.Down( "Duck" );
		var duckPressed = duckDown && !_prevDuckDown;
		_prevDuckDown = duckDown;

		if ( !IsSliding && duckPressed && IsSprinting && cc.IsOnGround )
		{
			var horizVel = cc.Velocity.WithZ( 0 );
			if ( horizVel.Length > WalkSpeed * 0.9f )
			{
				IsSliding = true;
				_slideTimeLeft = SlideDuration;
				_slideDirection = horizVel.Normal;
				// Initial boost
				cc.Velocity = (_slideDirection * horizVel.Length * SlideInitialBoost).WithZ( cc.Velocity.z );
				IsSprinting = false;
			}
		}

		if ( cc.IsOnGround && Input.Down( "Jump" ) && !IsSliding )
		{
			cc.Punch( Vector3.Up * JumpStrength );
			OnJump();
		}

		if ( IsSliding )
		{
			// Lock movement: ignore input direction, decay velocity along slide dir.
			var horizVel = cc.Velocity.WithZ( 0 );
			var speed = horizVel.Length;
			speed = Math.Max( 0f, speed - SlideDrag * Time.Delta * speed );
			cc.Velocity = (_slideDirection * speed).WithZ( cc.Velocity.z );
			_slideTimeLeft -= Time.Delta;

			if ( _slideTimeLeft <= 0f || speed < WalkSpeed * 0.5f )
			{
				IsSliding = false;
			}
		}
		else if ( cc.IsOnGround )
		{
			cc.Velocity = cc.Velocity.WithZ( 0 );
			cc.Accelerate( WishVelocity );
			cc.ApplyFriction( 4f );
		}
		else
		{
			cc.Velocity -= Gravity * Time.Delta * 0.5f;
			cc.Accelerate( WishVelocity.ClampLength( 50 ) );
			cc.ApplyFriction( 0.1f );
		}

		if ( !cc.IsOnGround )
			_lastAirborneVz = cc.Velocity.z;

		cc.Move();

		if ( !cc.IsOnGround )
			cc.Velocity -= Gravity * Time.Delta * 0.5f;
		else if ( !IsSliding )
			cc.Velocity = cc.Velocity.WithZ( 0 );

		// Landing detection.
		if ( cc.IsOnGround && !_wasOnGround && _lastAirborneVz < -50f )
			OnLand( -_lastAirborneVz );

		// Footstep distance integration. No footstep sounds while sliding.
		if ( cc.IsOnGround && !IsSliding )
		{
			var step = cc.Velocity.WithZ( 0 ).Length * Time.Delta;
			_stepAccumulator += step;
			var stride = FootstepDistance;
			if ( IsSprinting ) stride *= 0.75f;
			if ( IsCrouched ) stride *= 1.4f;        // slower cadence when sneaking
			if ( _stepAccumulator >= stride )
			{
				_stepAccumulator = 0f;
				PlayFootstep();
			}
		}
		else
		{
			_stepAccumulator = 0f;
		}

		// Stamina: drain while sprinting (only if actually moving), refill otherwise.
		var moving = cc.Velocity.WithZ( 0 ).Length > WalkSpeed * 0.5f;
		if ( IsSprinting && moving )
			Stamina = Math.Max( 0f, Stamina - Time.Delta / Math.Max( 0.1f, StaminaMaxSeconds ) );
		else
			Stamina = Math.Min( 1f, Stamina + Time.Delta / Math.Max( 0.1f, StaminaRefillSeconds ) );

		_wasOnGround = cc.IsOnGround;
	}

	void BuildWishVelocity()
	{
		if ( IsSliding )
		{
			// During slide, ignore input — the slide locks direction.
			WishVelocity = Vector3.Zero;
			return;
		}

		var rot = EyeAngles.ToRotation();
		WishVelocity = (rot * Input.AnalogMove).WithZ( 0 );
		if ( !WishVelocity.IsNearZeroLength ) WishVelocity = WishVelocity.Normal;
		var baseSpeed = IsSprinting ? SprintSpeed : WalkSpeed;
		// ADS slows movement.
		var adsScale = MathX.Lerp( 1f, AdsMovementMultiplier, _adsT );
		// Crouch slows movement.
		var crouchScale = MathX.Lerp( 1f, CrouchSpeedMultiplier, _crouchT );
		WishVelocity *= baseSpeed * adsScale * crouchScale;
	}

	void ResolvePrefabReferences()
	{
		if ( !Body.IsValid() )
			Body = GameObject.Children.FirstOrDefault( x => x.Name == "Body" );

		if ( !Eye.IsValid() )
			Eye = GameObject.Children.FirstOrDefault( x => x.Name == "Eye" );

		if ( !AnimationHelper.IsValid() && Body.IsValid() &&
			Body.Components.TryGet<CitizenAnimationHelper>( out var helper, FindMode.EverythingInSelfAndDescendants ) )
		{
			AnimationHelper = helper;
		}
	}

	[Rpc.Broadcast]
	void OnJump()
	{
		AnimationHelper?.TriggerJump();
		if ( JumpSound is not null )
			Sound.Play( JumpSound, WorldPosition );
	}

	void OnLand( float fallSpeed )
	{
		var t = (fallSpeed / LandingDipSpeedReference).Clamp( 0f, 1f );
		_landingDipPitch = LandingDipDegreesMax * t;
		BroadcastLand( fallSpeed );
	}

	[Rpc.Broadcast]
	void BroadcastLand( float fallSpeed )
	{
		if ( LandSound is null ) return;
		var volume = (fallSpeed / LandingDipSpeedReference).Clamp( 0.3f, 1.2f );
		var h = Sound.Play( LandSound, WorldPosition );
		if ( h is not null && h.IsValid )
			h.Volume = volume;
	}

	[Rpc.Broadcast]
	void PlayFootstep()
	{
		if ( FootstepSound is null ) return;
		Sound.Play( FootstepSound, WorldPosition );
	}
}
