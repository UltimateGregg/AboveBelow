using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Surface-aware impact feedback for hitscan bullets. Branches on the trace
/// surface to play the right "thwack" / "ping" / "thud" sound at the hit
/// position. Visual decals + particles are a future polish pass — they
/// require texture / .vpcf assets we don't have yet.
///
/// Call from inside <c>[Rpc.Broadcast]</c> fire-fx handlers so every peer
/// hears the impact, not just the shooter.
/// </summary>
public static class ImpactEffects
{
	public enum SurfaceKind { Default, Concrete, Metal, Flesh, Wood }

	/// <summary>
	/// Play the appropriate impact sound at the trace's hit point. Skips
	/// silently if the trace didn't hit anything.
	/// </summary>
	public static void Spawn( SceneTraceResult tr )
	{
		if ( !tr.Hit ) return;

		var kind = ClassifySurface( tr );
		var sound = SoundPathFor( kind );
		if ( !string.IsNullOrEmpty( sound ) )
			Sound.Play( sound, tr.HitPosition );
	}

	/// <summary>
	/// Explicit-kind variant for callers that already know what they hit
	/// (e.g. hit a Health component → SurfaceKind.Flesh, no need to inspect
	/// the trace surface).
	/// </summary>
	public static void Spawn( Vector3 position, SurfaceKind kind )
	{
		var sound = SoundPathFor( kind );
		if ( !string.IsNullOrEmpty( sound ) )
			Sound.Play( sound, position );
	}

	static SurfaceKind ClassifySurface( SceneTraceResult tr )
	{
		var name = tr.Surface?.ResourceName?.ToLowerInvariant() ?? "";

		if ( string.IsNullOrEmpty( name ) )
			return SurfaceKind.Default;

		// Heuristic substring matches — surface names vary across imported
		// assets so do simple keyword detection rather than exact equality.
		if ( name.Contains( "flesh" ) || name.Contains( "skin" ) || name.Contains( "body" ) )
			return SurfaceKind.Flesh;
		if ( name.Contains( "metal" ) || name.Contains( "steel" ) || name.Contains( "alum" ) )
			return SurfaceKind.Metal;
		if ( name.Contains( "wood" ) || name.Contains( "plank" ) )
			return SurfaceKind.Wood;
		if ( name.Contains( "concrete" ) || name.Contains( "stone" ) || name.Contains( "brick" ) )
			return SurfaceKind.Concrete;

		return SurfaceKind.Default;
	}

	static string SoundPathFor( SurfaceKind kind ) => kind switch
	{
		SurfaceKind.Metal    => "sounds/impact_metal.sound",
		SurfaceKind.Flesh    => "sounds/impact_flesh.sound",
		SurfaceKind.Wood     => "sounds/impact_concrete.sound",   // reuse concrete until we author a wood thud
		SurfaceKind.Concrete => "sounds/impact_concrete.sound",
		_                    => "sounds/impact_concrete.sound",
	};
}
