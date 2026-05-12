using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Plays a sound on a loop at the GameObject's world position. Restarts the
/// sound when the previous instance finishes. Use for scene-wide ambient
/// audio (battlefield wind, distant gunfire, etc.) — attach to a single
/// empty GameObject in main.scene.
/// </summary>
[Title( "Ambient Sound" )]
[Category( "Drone vs Players" )]
[Icon( "graphic_eq" )]
public sealed class AmbientSound : Component
{
	[Property] public SoundEvent Sound { get; set; }
	[Property, Range( 0f, 2f )] public float VolumeScale { get; set; } = 1f;

	SoundHandle _handle;

	protected override void OnStart()
	{
		Restart();
	}

	protected override void OnUpdate()
	{
		if ( Sound is null ) return;
		if ( _handle is null || !_handle.IsValid || _handle.IsStopped )
			Restart();
	}

	protected override void OnDestroy()
	{
		if ( _handle is not null && _handle.IsValid )
			_handle.Stop( 0.1f );
		_handle = null;
	}

	void Restart()
	{
		if ( Sound is null ) return;
		_handle = Sandbox.Sound.Play( Sound, WorldPosition );
		if ( _handle is not null && _handle.IsValid )
		{
			_handle.Volume = VolumeScale;
			_handle.Parent = GameObject;
		}
	}
}
