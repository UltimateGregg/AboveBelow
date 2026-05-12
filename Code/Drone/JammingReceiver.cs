using Sandbox;
using System;
using System.Collections.Generic;
using System.Linq;

namespace DroneVsPlayers;

/// <summary>
/// Receives "jam" pulses from drone-counter equipment (drone gun, chaff,
/// EMP). Tracks active sources host-side, exposes a synced flag clients
/// read to drive HUD + input gating.
///
/// Susceptibility is read from a sibling DroneBase: a value of 0 means the
/// drone is fully immune (e.g. fiber-optic FPV) and stays controllable
/// regardless of incoming jams.
/// </summary>
[Title( "Jamming Receiver" )]
[Category( "Drone vs Players/Drone" )]
[Icon( "signal_disconnected" )]
public sealed class JammingReceiver : Component
{
	[Property] public DroneController Drone { get; set; }
	[Property] public DroneBase DroneBase { get; set; }

	/// <summary>True whenever any jam source is currently affecting this drone.</summary>
	[Sync] public bool IsJammed { get; set; }

	/// <summary>Raw incoming jam strength [0..1] before susceptibility is applied.</summary>
	[Sync] public float IncomingStrength { get; set; }

	readonly List<JamSource> _sources = new();

	protected override void OnStart()
	{
		ResolveRefs();
	}

	protected override void OnUpdate()
	{
		ResolveRefs();

		if ( Networking.IsHost )
			TickHost();

		// Every peer drives its own input gate based on the synced flag, so the
		// drone's owner (who reads input) sees the effect.
		if ( Drone.IsValid() )
		{
			var effective = EffectiveJam();
			Drone.InputEnabled = !(effective > 0.01f) && !IsCrashing();
		}
	}

	void TickHost()
	{
		var now = Time.Now;
		_sources.RemoveAll( s => s.ExpiresAt <= now );

		var strongest = 0f;
		foreach ( var s in _sources )
			if ( s.Strength > strongest ) strongest = s.Strength;

		IncomingStrength = strongest;
		IsJammed = strongest > 0.01f;
	}

	float EffectiveJam()
	{
		if ( !DroneBase.IsValid() ) return IsJammed ? IncomingStrength : 0f;
		return IncomingStrength * DroneBase.JamSusceptibility;
	}

	bool IsCrashing()
	{
		var link = Components.Get<PilotLink>();
		return link.IsValid() && link.IsCrashing;
	}

	/// <summary>
	/// Apply a jamming pulse. Called by drone-counter equipment via RPC so
	/// every peer accumulates the same source list (host filters by authority).
	/// </summary>
	[Rpc.Broadcast]
	public void ApplyJam( System.Guid sourceId, float strength, float duration )
	{
		if ( !Networking.IsHost ) return;
		if ( duration <= 0f ) return;
		if ( strength <= 0f ) return;

		var expires = Time.Now + duration;
		// If the same source is re-applying, refresh rather than stack.
		for ( int i = 0; i < _sources.Count; i++ )
		{
			if ( _sources[i].SourceId == sourceId )
			{
				var existing = _sources[i];
				existing.Strength = MathF.Max( existing.Strength, strength );
				existing.ExpiresAt = MathF.Max( existing.ExpiresAt, expires );
				_sources[i] = existing;
				return;
			}
		}

		_sources.Add( new JamSource { SourceId = sourceId, Strength = strength, ExpiresAt = expires } );
	}

	void ResolveRefs()
	{
		if ( !Drone.IsValid() )
			Drone = Components.Get<DroneController>();
		if ( !DroneBase.IsValid() )
			DroneBase = Components.Get<DroneBase>();
	}
}
