using Sandbox;

namespace DroneVsPlayers;

/// <summary>
/// MGS-style chaff grenade. Brief, small-radius cloud of metallic particles
/// that scrambles drone signals — applies a short-duration jam to every
/// drone in radius. No damage to soldiers.
/// </summary>
[Title( "Chaff Grenade" )]
[Category( "Drone vs Players/Equipment" )]
[Icon( "blur_on" )]
public sealed class ChaffGrenade : ThrowableGrenade
{
	[Property] public float Radius { get; set; } = 600f;
	[Property] public float JamDuration { get; set; } = 3f;
	[Property, Range( 0f, 1f )] public float Strength { get; set; } = 1f;
	[Property] public GameObject EffectPrefab { get; set; }

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

		GrenadeEffectVisual.Spawn( center, GrenadeEffectKind.Chaff, Radius );
	}
}
