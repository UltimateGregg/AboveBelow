using System;
using System.Collections.Generic;
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
	/// <summary>
	/// Source length for ambience that should restart before the previous pass ends.
	/// Leave at zero to restart only after the sound handle stops.
	/// </summary>
	[Property, Range( 0f, 120f )] public float LoopDurationSeconds { get; set; } = 0f;

	/// <summary>
	/// How long the next ambience pass should play under the current one.
	/// </summary>
	[Property, Range( 0f, 10f )] public float LoopOverlapSeconds { get; set; } = 0f;

	readonly List<SoundHandle> _handles = new();
	TimeSince _timeSinceRestart = 999f;

	protected override void OnStart()
	{
		Restart();
	}

	protected override void OnUpdate()
	{
		if ( Sound is null )
		{
			StopAll( 0.1f );
			return;
		}

		RemoveStoppedHandles();
		if ( _handles.Count == 0 )
		{
			Restart();
			return;
		}

		UpdateHandles();
		if ( ShouldOverlapRestart() )
			Restart();
	}

	protected override void OnDestroy()
	{
		StopAll( 0.1f );
	}

	void Restart()
	{
		if ( Sound is null ) return;

		var fadeIn = _handles.Count > 0 ? MathF.Min( LoopOverlapSeconds, 0.5f ) : 0.2f;
		var handle = Sandbox.Sound.Play( Sound, WorldPosition, fadeIn );
		if ( handle is not null && handle.IsValid )
		{
			handle.Volume = VolumeScale;
			handle.Parent = GameObject;
			_handles.Add( handle );
			_timeSinceRestart = 0f;
		}
	}

	bool ShouldOverlapRestart()
	{
		if ( LoopDurationSeconds <= 0f || LoopOverlapSeconds <= 0f )
			return false;

		var overlap = MathF.Min( LoopOverlapSeconds, MathF.Max( 0f, LoopDurationSeconds - 0.05f ) );
		if ( overlap <= 0f )
			return false;

		var restartAfter = LoopDurationSeconds - overlap;
		return _timeSinceRestart >= restartAfter;
	}

	void UpdateHandles()
	{
		foreach ( var handle in _handles )
		{
			if ( handle is null || !handle.IsValid ) continue;
			handle.Position = WorldPosition;
			handle.Volume = VolumeScale;
			handle.Parent = GameObject;
		}
	}

	void RemoveStoppedHandles()
	{
		_handles.RemoveAll( handle => handle is null || !handle.IsValid || handle.IsStopped );
	}

	void StopAll( float fadeTime )
	{
		foreach ( var handle in _handles )
		{
			if ( handle is not null && handle.IsValid )
				handle.Stop( fadeTime );
		}

		_handles.Clear();
	}
}
