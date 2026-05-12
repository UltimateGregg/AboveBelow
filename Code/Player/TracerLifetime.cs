using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Destroys a bullet tracer GameObject after a short lifetime. The tracer
/// is spawned per-shot by <c>HitscanWeapon.PlayFireFx</c> / <c>ShotgunWeapon.PlayFireFx</c>.
/// The caller is responsible for setting the LineRenderer's
/// <c>VectorPoints</c> to <c>[from, to]</c> immediately after
/// <c>TracerPrefab.Clone(...)</c>.
/// </summary>
[Title( "Tracer Lifetime" )]
[Category( "Drone vs Players/Player" )]
[Icon( "show_chart" )]
public sealed class TracerLifetime : Component
{
	[Property, Range( 0.02f, 1.0f )] public float Lifetime { get; set; } = 0.08f;

	TimeSince _timeSinceSpawn;

	protected override void OnStart()
	{
		_timeSinceSpawn = 0f;
	}

	protected override void OnUpdate()
	{
		if ( _timeSinceSpawn >= Lifetime )
			GameObject.Destroy();
	}
}
