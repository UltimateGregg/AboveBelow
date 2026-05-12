using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// Heavier electromagnetic-pulse grenade. Bigger radius and longer jam
/// duration than chaff. Slower fuse to compensate. Also harmless to
/// soldiers — pure area denial against drones.
/// </summary>
[Title( "EMP Grenade" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "bolt" )]
public sealed class EmpGrenade : ThrowableGrenade
{
	[Property] public float Radius { get; set; } = 1100f;
	[Property] public float JamDuration { get; set; } = 6f;
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;
	[Property] public GameObject EffectPrefab { get; set; }

	public EmpGrenade()
	{
		FuseSeconds = 2.5f;
		Cooldown = 8f;
	}

	protected override void OnDetonate( Vector3 worldPos )
	{
		BroadcastEffect( worldPos );
		ApplyJamArea( worldPos, Radius, Strength, JamDuration, GameObject.Id );
	}

	[Rpc.Broadcast]
	void ApplyJamArea( Vector3 center, float radius, float strength, float duration, System.Guid sourceId )
	{
		if ( !Networking.IsHost ) return;

		foreach ( var receiver in Scene.GetAllComponents<JammingReceiver>() )
		{
			if ( !receiver.IsValid() ) continue;
			var dist = (receiver.WorldPosition - center).Length;
			if ( dist > radius ) continue;
			receiver.ApplyJam( sourceId, strength, duration );
		}
	}

	[Rpc.Broadcast]
	void BroadcastEffect( Vector3 center )
	{
		if ( EffectPrefab.IsValid() )
		{
			EffectPrefab.Clone( center );
			return;
		}

		GrenadeEffectVisual.Spawn( center, GrenadeEffectKind.Emp, Radius );
	}
}
